import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';

import '../data/models/promotion_batch.dart';
import '../data/models/promotion_preview.dart';
import '../data/promotion_repository.dart';

/// The promotion wizard's state (docs/promotion.md).
///
/// Two steps so far: choose the section and the year, then read the roster
/// and set an outcome per student. The chosen outcomes are held here rather
/// than in the widget because they are the thing the run will be given, and
/// because a search box that filters the list must not lose what has been
/// decided about the rows it hides.
///
/// The run is the last step and the only one that writes: it sends the
/// decisions as they stand, and what comes back is the batch, which the
/// screen shows instead of the roster it was working on.
final promotionNotifierProvider = NotifierProvider<PromotionNotifier, PromotionState>(PromotionNotifier.new);

class PromotionState {
  const PromotionState({
    this.classSectionId,
    this.toAcademicYearId,
    this.toClassSectionId,
    this.preview = const AsyncValue<PromotionPreview?>.data(null),
    this.outcomes = const {},
    this.search = '',
    this.isRunning = false,
    this.completed,
    this.error,
  });

  /// What was asked for.
  final int? classSectionId;
  final int? toAcademicYearId;
  final int? toClassSectionId;

  /// The answer. Null data means nothing has been asked yet, which is the
  /// screen's first step rather than an empty result.
  final AsyncValue<PromotionPreview?> preview;

  /// What the administrator has decided, per student. Seeded from the
  /// server's defaults and changed only by hand.
  final Map<int, PromotionOutcome> outcomes;

  final String search;

  /// True while the run is in flight, so the button cannot be pressed twice
  /// - and a promotion is the last thing that should happen twice.
  final bool isRunning;

  /// The batch, once it has run. The screen shows this instead of the
  /// roster, because the roster describes a class that has just changed.
  final PromotionBatch? completed;

  /// What the server said when it refused, shown above the list it refers
  /// to rather than in a snackbar that disappears.
  final String? error;

  bool get hasPreview => preview.value != null;

  bool get hasRun => completed != null;

  /// Everything needed to ask for a preview at all.
  bool get canPreview => classSectionId != null && toAcademicYearId != null;

  PromotionState copyWith({
    int? classSectionId,
    int? toAcademicYearId,
    int? toClassSectionId,
    bool clearTargetSection = false,
    AsyncValue<PromotionPreview?>? preview,
    Map<int, PromotionOutcome>? outcomes,
    String? search,
    bool? isRunning,
    PromotionBatch? completed,
    bool clearCompleted = false,
    String? error,
    bool clearError = false,
  }) {
    return PromotionState(
      classSectionId: classSectionId ?? this.classSectionId,
      toAcademicYearId: toAcademicYearId ?? this.toAcademicYearId,
      toClassSectionId: clearTargetSection ? null : (toClassSectionId ?? this.toClassSectionId),
      preview: preview ?? this.preview,
      outcomes: outcomes ?? this.outcomes,
      search: search ?? this.search,
      isRunning: isRunning ?? this.isRunning,
      completed: clearCompleted ? null : (completed ?? this.completed),
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// The rows the list shows: everybody, or those matching the search box by
  /// name or admission number.
  List<PromotionStudent> get visibleStudents {
    final students = preview.value?.students ?? const <PromotionStudent>[];
    final term = search.trim().toLowerCase();

    if (term.isEmpty) return students;

    return students
        .where(
          (student) =>
              student.name.toLowerCase().contains(term) || student.admissionNumber.toLowerCase().contains(term),
        )
        .toList(growable: false);
  }

  PromotionOutcome outcomeFor(PromotionStudent student) => outcomes[student.studentId] ?? student.defaultOutcome;

  /// How many students each outcome would apply to - counted over everybody,
  /// never only the rows a search happens to be showing, because the run
  /// applies to the whole class.
  Map<PromotionOutcome, int> get counts {
    final counted = {for (final outcome in PromotionOutcome.values) outcome: 0};

    for (final student in preview.value?.students ?? const <PromotionStudent>[]) {
      if (student.isBlocked) continue;

      counted[outcomeFor(student)] = (counted[outcomeFor(student)] ?? 0) + 1;
    }

    return counted;
  }
}

class PromotionNotifier extends Notifier<PromotionState> {
  @override
  PromotionState build() => const PromotionState();

  /// Choosing anything on step one drops the roster: it describes the
  /// section that was asked about, and showing it beside a different choice
  /// would be showing the wrong class.
  void setSourceSection(int? classSectionId) {
    state = _reset(state.copyWith(classSectionId: classSectionId));
  }

  void setTargetYear(int? academicYearId) {
    // The target section belonged to the old year, so it goes with it.
    state = _reset(state.copyWith(toAcademicYearId: academicYearId, clearTargetSection: true));
  }

  void setTargetSection(int? classSectionId) {
    state = _reset(
      classSectionId == null
          ? state.copyWith(clearTargetSection: true)
          : state.copyWith(toClassSectionId: classSectionId),
    );
  }

  PromotionState _reset(PromotionState next) {
    return next.copyWith(preview: const AsyncValue<PromotionPreview?>.data(null), outcomes: const {}, search: '');
  }

  /// Step two: ask what would happen.
  Future<void> loadPreview() async {
    if (!state.canPreview) return;

    state = state.copyWith(preview: const AsyncValue<PromotionPreview?>.loading());
    state = state.copyWith(
      preview: await AsyncValue.guard<PromotionPreview?>(
        () => ref
            .read(promotionRepositoryProvider)
            .preview(
              classSectionId: state.classSectionId!,
              toAcademicYearId: state.toAcademicYearId!,
              toClassSectionId: state.toClassSectionId,
            ),
      ),
      outcomes: const {},
    );
  }

  /// Back to step one, keeping the choices that got here so the screen does
  /// not ask for them twice.
  void backToChoices() {
    state = state.copyWith(
      preview: const AsyncValue<PromotionPreview?>.data(null),
      outcomes: const {},
      search: '',
      clearCompleted: true,
      clearError: true,
    );
  }

  /// Runs the batch as it stands on screen.
  ///
  /// Every student in the roster is sent, blocked ones excepted: they cannot
  /// be moved, and naming them would only earn the whole batch a refusal.
  Future<bool> run() async {
    final preview = state.preview.value;

    if (preview == null || state.isRunning || state.hasRun) return false;

    final outcomes = {
      for (final student in preview.students)
        if (!student.isBlocked) student.studentId: state.outcomeFor(student).apiValue,
    };

    if (outcomes.isEmpty) return false;

    state = state.copyWith(isRunning: true, clearError: true);

    try {
      final batch = await ref
          .read(promotionRepositoryProvider)
          .run(
            classSectionId: state.classSectionId!,
            toAcademicYearId: state.toAcademicYearId!,
            toClassSectionId: state.toClassSectionId,
            outcomes: outcomes,
          );

      state = state.copyWith(isRunning: false, completed: batch);

      return true;
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      state = state.copyWith(isRunning: false, error: failure.message);

      return false;
    }
  }

  /// After a run: start again from the first step, with nothing carried over.
  void startAgain() {
    state = const PromotionState();
  }

  void setOutcome(int studentId, PromotionOutcome outcome) {
    state = state.copyWith(outcomes: {...state.outcomes, studentId: outcome});
  }

  /// A bulk action over the rows the search is showing, never over the rows
  /// it is hiding: "promote all" on a filtered list means the list in front
  /// of the person reading it.
  void setOutcomeForVisible(PromotionOutcome outcome) {
    final changed = {...state.outcomes};

    for (final student in state.visibleStudents) {
      if (student.isBlocked) continue;

      changed[student.studentId] = outcome;
    }

    state = state.copyWith(outcomes: changed);
  }

  /// Puts every row back to what the server suggested.
  void resetOutcomes() {
    state = state.copyWith(outcomes: const {});
  }

  void setSearch(String term) {
    state = state.copyWith(search: term);
  }
}
