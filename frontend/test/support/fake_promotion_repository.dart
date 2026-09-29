import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/promotion/data/models/promotion_batch.dart';
import 'package:edutrack_app/features/promotion/data/models/promotion_preview.dart';
import 'package:edutrack_app/features/promotion/data/promotion_repository.dart';

/// A promotion preview without a server (docs/promotion.md).
class FakePromotionRepository implements PromotionRepository {
  FakePromotionRepository({
    PromotionPreview? preview,
    this.failure,
    this.runFailure,
    PromotionBatch? batch,
    List<PromotionBatch>? history,
  }) : _preview = preview ?? fakePreview(),
       _batch = batch ?? fakeBatch(),
       _history = history ?? const [];

  final PromotionPreview _preview;
  final PromotionBatch _batch;
  final List<PromotionBatch> _history;
  final Failure? failure;

  /// Thrown by [run] alone, so a test can refuse the write while the
  /// preview still reads.
  final Failure? runFailure;

  Map<int, String>? lastRun;
  int runs = 0;

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

  @override
  Future<PromotionBatch> run({
    required int classSectionId,
    required int toAcademicYearId,
    int? toClassSectionId,
    required Map<int, String> outcomes,
  }) async {
    runs++;
    lastRun = outcomes;
    lastCall = {
      'class_section_id': classSectionId,
      'to_academic_year_id': toAcademicYearId,
      'to_class_section_id': toClassSectionId,
    };

    if (runFailure != null) throw runFailure!;

    return _batch;
  }

  @override
  Future<PaginatedResponse<PromotionBatch>> history({int? page, int? perPage, int? academicYearId}) async {
    if (failure != null) throw failure!;

    return PaginatedResponse(
      items: _history,
      currentPage: page ?? 1,
      lastPage: 1,
      total: _history.length,
      perPage: perPage ?? 20,
    );
  }

  @override
  Future<PromotionBatch> batch(int batchId) async {
    if (failure != null) throw failure!;

    return _batch;
  }
}

PromotionBatch fakeBatch({
  int id = 7,
  int promoted = 2,
  int retained = 1,
  int graduated = 0,
  int left = 0,
  String? toClassSectionName = 'Grade 9 A',
  List<PromotionBatchStudent>? students,
}) {
  return PromotionBatch(
    id: id,
    fromAcademicYearName: '2026-27',
    toAcademicYearName: '2027-28',
    fromClassSectionName: 'Grade 8 A',
    toClassSectionName: toClassSectionName,
    promotedCount: promoted,
    retainedCount: retained,
    graduatedCount: graduated,
    leftCount: left,
    studentCount: promoted + retained + graduated + left,
    runByName: 'Asha Admin',
    runAt: DateTime(2027, 3, 31, 9, 30),
    students:
        students ??
        const [
          PromotionBatchStudent(
            studentId: 1,
            name: 'Aarav Sharma',
            admissionNumber: 'ADM-1',
            rollNumber: '1',
            fromClassName: 'Grade 8',
            fromSectionName: 'A',
            outcome: 'promoted',
            toClassName: 'Grade 9',
            toSectionName: 'A',
          ),
          PromotionBatchStudent(
            studentId: 2,
            name: 'Bina Kapoor',
            admissionNumber: 'ADM-2',
            rollNumber: '2',
            fromClassName: 'Grade 8',
            fromSectionName: 'A',
            outcome: 'graduated',
            toClassName: null,
            toSectionName: null,
          ),
        ],
  );
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
