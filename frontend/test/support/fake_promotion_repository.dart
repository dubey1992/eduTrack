import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/promotion/data/models/promotion_preview.dart';
import 'package:edutrack_app/features/promotion/data/promotion_repository.dart';

/// A promotion preview without a server (docs/promotion.md).
class FakePromotionRepository implements PromotionRepository {
  FakePromotionRepository({PromotionPreview? preview, this.failure}) : _preview = preview ?? fakePreview();

  final PromotionPreview _preview;
  final Failure? failure;

  /// What the screen last asked for, so a test can check the section and the
  /// year really travelled.
  Map<String, Object?>? lastCall;
  int calls = 0;

  @override
  Future<PromotionPreview> preview({
    required int classSectionId,
    required int toAcademicYearId,
    int? toClassSectionId,
  }) async {
    calls++;
    lastCall = {
      'class_section_id': classSectionId,
      'to_academic_year_id': toAcademicYearId,
      'to_class_section_id': toClassSectionId,
    };

    if (failure != null) throw failure!;

    return _preview;
  }
}

PromotionStudent fakePromotionStudent({
  int studentId = 1,
  String name = 'Aarav Sharma',
  String admissionNumber = 'ADM-1',
  String? rollNumber = '1',
  PromotionOutcome defaultOutcome = PromotionOutcome.promote,
  bool isBlocked = false,
  String? blockedReason,
  String? averagePercentage,
  double? attendancePercentage,
  PromotionOutcome? suggestedOutcome,
  String? suggestionReason,
}) {
  return PromotionStudent(
    studentId: studentId,
    name: name,
    admissionNumber: admissionNumber,
    rollNumber: rollNumber,
    status: 'active',
    defaultOutcome: defaultOutcome,
    isBlocked: isBlocked,
    blockedReason: blockedReason,
    averagePercentage: averagePercentage,
    attendancePercentage: attendancePercentage,
    suggestedOutcome: suggestedOutcome,
    suggestionReason: suggestionReason,
  );
}

PromotionPreview fakePreview({
  List<PromotionStudent>? students,
  bool isGraduating = false,
  bool canRun = true,
  String? cannotRunReason,
  String? targetName = 'Grade 9 A',
  bool isSuggested = true,
  PromotionSuggestions suggestions = const PromotionSuggestions(
    available: true,
    termName: 'Term 3',
    passPercentage: '33',
  ),
}) {
  return PromotionPreview(
    from: const PromotionSide(
      academicYearId: 1,
      academicYearName: '2026-27',
      classSectionId: 10,
      classSectionName: 'Grade 8 A',
      schoolClassId: 5,
      schoolClassName: 'Grade 8',
    ),
    to: PromotionSide(
      academicYearId: 2,
      academicYearName: '2027-28',
      classSectionId: targetName == null ? null : 20,
      classSectionName: targetName,
      schoolClassId: targetName == null ? null : 6,
      schoolClassName: targetName == null ? null : 'Grade 9',
      isSuggested: isSuggested,
    ),
    isGraduating: isGraduating,
    canRun: canRun,
    cannotRunReason: cannotRunReason,
    suggestions: suggestions,
    students:
        students ??
        [
          fakePromotionStudent(),
          fakePromotionStudent(studentId: 2, name: 'Bina Kapoor', admissionNumber: 'ADM-2', rollNumber: '2'),
        ],
  );
}
