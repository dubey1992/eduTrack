import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/family_repository.dart';
import '../data/models/family_absence_note.dart';
import '../data/models/family_bus.dart';
import '../data/models/family_fees.dart';
import '../data/models/family_learning.dart';

/// One child's results for one term, keyed by (child, term id or null for
/// the term being lived).
final familyResultsProvider = AsyncNotifierProvider.autoDispose
    .family<FamilyResultsNotifier, FamilyResults, (int, int?)>(
      FamilyResultsNotifier.new,
      // A failure is shown with its own retry, not retried behind the parent's back.
      retry: (retryCount, error) => null,
    );

class FamilyResultsNotifier extends AsyncNotifier<FamilyResults> {
  FamilyResultsNotifier(this.key);

  final (int, int?) key;

  @override
  Future<FamilyResults> build() => ref.read(familyRepositoryProvider).results(key.$1, termId: key.$2);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final familyWeekProvider = AsyncNotifierProvider.autoDispose.family<FamilyWeekNotifier, FamilyWeek, int>(
  FamilyWeekNotifier.new,
  retry: (retryCount, error) => null,
);

class FamilyWeekNotifier extends AsyncNotifier<FamilyWeek> {
  FamilyWeekNotifier(this.childId);

  final int childId;

  @override
  Future<FamilyWeek> build() => ref.read(familyRepositoryProvider).timetable(childId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final familySyllabusProvider = AsyncNotifierProvider.autoDispose
    .family<FamilySyllabusNotifier, List<SubjectSyllabus>, int>(
      FamilySyllabusNotifier.new,
      retry: (retryCount, error) => null,
    );

class FamilySyllabusNotifier extends AsyncNotifier<List<SubjectSyllabus>> {
  FamilySyllabusNotifier(this.childId);

  final int childId;

  @override
  Future<List<SubjectSyllabus>> build() => ref.read(familyRepositoryProvider).syllabus(childId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

/// One child's fees for their current year (F3).
final familyFeesProvider = AsyncNotifierProvider.autoDispose.family<FamilyFeesNotifier, FamilyFees, int>(
  FamilyFeesNotifier.new,
  retry: (retryCount, error) => null,
);

class FamilyFeesNotifier extends AsyncNotifier<FamilyFees> {
  FamilyFeesNotifier(this.childId);

  final int childId;

  @override
  Future<FamilyFees> build() => ref.read(familyRepositoryProvider).fees(childId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

/// One child's bus: route, stop, contacts and today's trips (F4). Null for
/// a child not on a school bus.
final familyBusProvider = AsyncNotifierProvider.autoDispose.family<FamilyBusNotifier, FamilyBus?, int>(
  FamilyBusNotifier.new,
  retry: (retryCount, error) => null,
);

class FamilyBusNotifier extends AsyncNotifier<FamilyBus?> {
  FamilyBusNotifier(this.childId);

  final int childId;

  @override
  Future<FamilyBus?> build() => ref.read(familyRepositoryProvider).bus(childId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

/// One child's absence notes, newest first (F5).
final familyAbsenceNotesProvider = FutureProvider.autoDispose.family<List<FamilyAbsenceNote>, int>(
  (ref, childId) => ref.read(familyRepositoryProvider).absenceNotes(childId),
  retry: (retryCount, error) => null,
);
