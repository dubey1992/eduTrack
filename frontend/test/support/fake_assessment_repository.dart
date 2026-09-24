import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment.dart';
import 'package:edutrack_app/features/assessments/data/models/assessment_sheet.dart';
import 'package:edutrack_app/features/imports/data/import_repository.dart';

import 'fake_pagination.dart';

/// An in-memory stand-in for the class tests API.
///
/// It keeps the server's filtering, because the screen's filters are only
/// meaningful if something acts on them, and records what it was asked for
/// so a test can check the screen asked at all.
class FakeAssessmentRepository implements AssessmentRepository {
  FakeAssessmentRepository({
    List<Assessment>? assessments,
    List<SheetEntry>? sheetEntries,
    this.failWith = const {},
    this.refuseUploadWith,
  }) : _assessments = assessments ?? [],
       _sheetEntries = sheetEntries ?? [];

  final List<Assessment> _assessments;
  List<SheetEntry> _sheetEntries;

  /// The sheet the last save sent, so a test can check what went out.
  List<SheetEntry>? lastSaved;

  /// The file the last upload sent.
  String? lastUploadedFileName;

  /// What a refused upload answers with, when a test asks for one.
  final BulkImportFailure? refuseUploadWith;

  /// Keyed by method name: {'create': Failure(...)}.
  final Map<String, Failure> failWith;

  final List<String> calls = [];

  /// The filters the screen last asked for.
  int? lastSectionFilter;
  String? lastStatusFilter;

  void _enter(String method) {
    calls.add(method);
    final failure = failWith[method];
    if (failure != null) throw failure;
  }

  @override
  Future<PaginatedResponse<Assessment>> listPage({
    int? schoolId,
    int? academicTermId,
    int? classSectionId,
    int? subjectId,
    String? status,
    String? type,
    required int page,
    required int perPage,
  }) async {
    _enter('listPage');
    lastSectionFilter = classSectionId;
    lastStatusFilter = status;

    final found = _assessments.where((row) {
      if (classSectionId != null && row.classSectionId != classSectionId) return false;
      if (subjectId != null && row.subjectId != subjectId) return false;
      if (academicTermId != null && row.academicTermId != academicTermId) return false;
      if (status != null && row.status.apiValue != status) return false;
      if (type != null && row.type.apiValue != type) return false;
      return true;
    }).toList();

    return paginateFake(found, page: page, perPage: perPage);
  }

  @override
  Future<Assessment> create({
    required int classSectionId,
    required int subjectId,
    required int academicTermId,
    int? syllabusTopicId,
    int? gradeScaleId,
    required String type,
    required String title,
    required String maxMarks,
    String? passMarks,
    String? weightage,
    required DateTime assessmentDate,
  }) async {
    _enter('create');

    final created = fakeAssessment(
      id: _assessments.length + 1,
      title: title,
      maxMarks: maxMarks,
      passMarks: passMarks,
      weightage: weightage,
      type: AssessmentType.fromApiValue(type),
      date: assessmentDate,
      classSectionId: classSectionId,
      subjectId: subjectId,
      academicTermId: academicTermId,
    );
    _assessments.add(created);

    return created;
  }

  @override
  Future<Assessment> update(
    int assessmentId, {
    int? academicTermId,
    int? gradeScaleId,
    String? type,
    String? title,
    String? maxMarks,
    String? passMarks,
    String? weightage,
    DateTime? assessmentDate,
  }) async {
    _enter('update');

    final index = _assessments.indexWhere((row) => row.id == assessmentId);
    final existing = _assessments[index];
    final updated = fakeAssessment(
      id: existing.id,
      title: title ?? existing.title,
      maxMarks: maxMarks ?? existing.maxMarks,
      passMarks: passMarks,
      weightage: weightage,
      type: type == null ? existing.type : AssessmentType.fromApiValue(type),
      date: assessmentDate ?? existing.assessmentDate,
      classSectionId: existing.classSectionId,
      subjectId: existing.subjectId,
      academicTermId: academicTermId ?? existing.academicTermId,
      status: existing.status,
    );
    _assessments[index] = updated;

    return updated;
  }

  @override
  Future<void> delete(int assessmentId) async {
    _enter('delete');
    _assessments.removeWhere((row) => row.id == assessmentId);
  }

  @override
  Future<AssessmentSheet> sheet(int assessmentId) async {
    _enter('sheet');

    return AssessmentSheet(
      assessment: fakeAssessment(id: assessmentId),
      entries: List.unmodifiable(_sheetEntries),
    );
  }

  @override
  Future<AssessmentSheet> saveMarks(int assessmentId, List<SheetEntry> entries) async {
    lastSaved = List.unmodifiable(entries);
    _enter('saveMarks');
    _sheetEntries = List.of(entries);

    return AssessmentSheet(
      assessment: fakeAssessment(id: assessmentId),
      entries: List.unmodifiable(_sheetEntries),
    );
  }

  @override
  Future<List<int>> marksTemplate(int assessmentId) async {
    _enter('marksTemplate');

    return 'admission_number,student_name,marks,absent,remarks'.codeUnits;
  }

  @override
  Future<AssessmentSheet> uploadMarks(int assessmentId, {required String fileName, required List<int> bytes}) async {
    lastUploadedFileName = fileName;
    _enter('uploadMarks');

    final refusal = refuseUploadWith;
    if (refusal != null) throw refusal;

    _sheetEntries = [for (final entry in _sheetEntries) entry.copyWith(marksObtained: '15')];

    return AssessmentSheet(
      assessment: fakeAssessment(id: assessmentId),
      entries: List.unmodifiable(_sheetEntries),
    );
  }
}

Assessment fakeAssessment({
  int id = 1,
  String title = 'Fractions - unit test',
  String maxMarks = '20.00',
  String? passMarks,
  String? weightage,
  AssessmentType type = AssessmentType.classTest,
  DateTime? date,
  int classSectionId = 3,
  String classSectionName = 'Grade 8 A',
  int subjectId = 5,
  String subjectName = 'Mathematics',
  int academicTermId = 2,
  String termName = 'Term 1',
  AssessmentStatus status = AssessmentStatus.draft,
  int? gradeScaleId,
  String? gradeScaleName,
}) {
  return Assessment(
    id: id,
    schoolId: 1,
    academicTermId: academicTermId,
    termName: termName,
    classSectionId: classSectionId,
    classSectionName: classSectionName,
    subjectId: subjectId,
    subjectName: subjectName,
    syllabusTopicId: null,
    syllabusTopicTitle: null,
    gradeScaleId: gradeScaleId,
    gradeScaleName: gradeScaleName,
    type: type,
    title: title,
    maxMarks: maxMarks,
    passMarks: passMarks,
    weightage: weightage,
    assessmentDate: date ?? DateTime(2026, 4, 15),
    status: status,
    createdByName: 'Asha Admin',
  );
}

SheetEntry fakeEntry({
  int studentId = 1,
  String name = 'Aarav Sharma',
  String admissionNumber = 'ADM-1',
  String? roll = '4',
  String? marks,
  bool isAbsent = false,
  String? grade,
}) {
  return SheetEntry(
    studentId: studentId,
    studentName: name,
    admissionNumber: admissionNumber,
    rollNumber: roll,
    marksObtained: marks,
    isAbsent: isAbsent,
    grade: grade,
    remarks: null,
  );
}

AssessmentSheet fakeSheet({Assessment? assessment, List<SheetEntry>? entries}) {
  return AssessmentSheet(assessment: assessment ?? fakeAssessment(), entries: entries ?? [fakeEntry()]);
}
