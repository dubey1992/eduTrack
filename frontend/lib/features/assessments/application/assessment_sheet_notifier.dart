import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/assessment_repository.dart';
import '../data/models/assessment_sheet.dart';

/// One test's marks sheet, keyed by the test.
///
/// Marks are edited in memory and written in one go, the way the attendance
/// register is: a class of forty entered on a phone cannot afford a request
/// per child, and a half-saved sheet is worse than an unsaved one.
final assessmentSheetProvider = AsyncNotifierProvider.autoDispose.family<AssessmentSheetNotifier, AssessmentSheet, int>(
  AssessmentSheetNotifier.new,
);

class AssessmentSheetNotifier extends AsyncNotifier<AssessmentSheet> {
  // Riverpod 3 does not hand the key to build(), so it is a constructor field.
  AssessmentSheetNotifier(this.assessmentId);

  final int assessmentId;

  /// Whether anything has been typed since the last save. The Save button
  /// reads this, so a teacher is not invited to save a sheet they have not
  /// touched.
  bool _dirty = false;

  bool get isDirty => _dirty;

  @override
  Future<AssessmentSheet> build() => _fetch();

  Future<AssessmentSheet> _fetch() async {
    final sheet = await ref.read(assessmentRepositoryProvider).sheet(assessmentId);
    _dirty = false;

    return sheet;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// Types a mark for one student. Nothing is sent until [save].
  void setMark(int studentId, String marks) {
    _edit(studentId, (entry) => entry.copyWith(marksObtained: marks, isAbsent: false, clearMarks: marks.isEmpty));
  }

  /// Marks a student absent, or takes it back. Absent is not zero, so the
  /// mark goes with it.
  void setAbsent(int studentId, bool isAbsent) {
    _edit(studentId, (entry) => entry.copyWith(isAbsent: isAbsent, clearMarks: isAbsent));
  }

  void _edit(int studentId, SheetEntry Function(SheetEntry) change) {
    final sheet = state.value;
    if (sheet == null) return;

    _dirty = true;
    state = AsyncData(
      AssessmentSheet(
        assessment: sheet.assessment,
        entries: [for (final entry in sheet.entries) entry.studentId == studentId ? change(entry) : entry],
      ),
    );
  }

  /// Sends the whole sheet. Throws on refusal, so the screen can show which
  /// row the server objected to.
  Future<void> save() async {
    final sheet = state.value;
    if (sheet == null) return;

    final saved = await ref.read(assessmentRepositoryProvider).saveMarks(assessmentId, sheet.entries);
    _dirty = false;
    state = AsyncData(saved);
  }

  /// Sends a filled-in spreadsheet. Throws with the rows that need fixing,
  /// so the screen can list them beside the sheet.
  Future<void> upload({required String fileName, required List<int> bytes}) async {
    final saved = await ref
        .read(assessmentRepositoryProvider)
        .uploadMarks(assessmentId, fileName: fileName, bytes: bytes);
    _dirty = false;
    state = AsyncData(saved);
  }

  Future<List<int>> template() => ref.read(assessmentRepositoryProvider).marksTemplate(assessmentId);

  Future<MarksPreview> preview({required String fileName, required List<int> bytes}) {
    return ref.read(assessmentRepositoryProvider).previewMarks(assessmentId, fileName: fileName, bytes: bytes);
  }
}
