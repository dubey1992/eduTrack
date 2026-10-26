import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report_summary.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';

class FakeTeachingReportRepository implements TeachingReportRepository {
  FakeTeachingReportRepository({
    this.reports = const [],
    this.summaryData = const TeachingReportSummary(scheduled: 0, submitted: 0, pending: 0),
    this.failStoreWith,
  });

  List<TeachingReport> reports;
  TeachingReportSummary summaryData;
  Failure? failStoreWith;
  Failure? failListWith;
  Failure? failGetWith;
  Failure? failReviewWith;
  Failure? failSendBackWith;
  Failure? failResubmitWith;
  String? lastReviewNote;
  String? lastSendBackNote;
  Map<String, String?>? lastResubmit;
  bool? lastListMine;
  bool? lastListToReview;
  (String?, String?)? lastListRange;

  Map<String, dynamic>? lastStorePayload;
  int? lastReviewedId;

  @override
  Future<TeachingReport> store({
    required int timetableEntryId,
    required String reportDate,
    required String topicTaught,
    int? syllabusTopicId,
    String? homework,
    String? remarks,
  }) async {
    if (failStoreWith != null) throw failStoreWith!;
    lastStorePayload = {
      'timetable_entry_id': timetableEntryId,
      'report_date': reportDate,
      'topic_taught': topicTaught,
      'syllabus_topic_id': syllabusTopicId,
      'homework': homework,
      'remarks': remarks,
    };
    final created = TeachingReport(
      id: reports.length + 1,
      schoolId: 1,
      timetableEntryId: timetableEntryId,
      classSectionName: 'Grade 8 A',
      periodNumber: 1,
      subjectName: 'Mathematics',
      teacherId: 20,
      teacherName: 'Priya Sharma',
      reportDate: reportDate,
      topicTaught: topicTaught,
      homework: homework,
      remarks: remarks,
      reviewedBy: null,
      reviewedByName: null,
      reviewedAt: null,
    );
    reports = [...reports, created];
    return created;
  }

  @override
  Future<PaginatedResponse<TeachingReport>> list({
    int? schoolId,
    int? teacherId,
    String? reportDate,
    bool mine = false,
    bool toReview = false,
    String? dateFrom,
    String? dateTo,
    required int page,
    required int perPage,
  }) async {
    lastListMine = mine;
    lastListToReview = toReview;
    lastListRange = (dateFrom, dateTo);
    if (failListWith != null) throw failListWith!;
    final filtered = reports.where((r) {
      if (schoolId != null && r.schoolId != schoolId) return false;
      if (teacherId != null && r.teacherId != teacherId) return false;
      if (reportDate != null && r.reportDate != reportDate) return false;
      return true;
    }).toList();

    return PaginatedResponse(items: filtered, currentPage: page, lastPage: 1, total: filtered.length, perPage: perPage);
  }

  @override
  Future<TeachingReport> get(int reportId) async {
    if (failGetWith != null) throw failGetWith!;
    return reports.firstWhere((r) => r.id == reportId);
  }

  @override
  Future<TeachingReportSummary> summary({int? schoolId, required String date}) async {
    return summaryData;
  }

  @override
  Future<TeachingReport> review(int reportId, {String? note}) async {
    if (failReviewWith != null) throw failReviewWith!;
    lastReviewedId = reportId;
    lastReviewNote = note;
    final existing = reports.firstWhere((r) => r.id == reportId);
    final updated = TeachingReport(
      id: existing.id,
      schoolId: existing.schoolId,
      timetableEntryId: existing.timetableEntryId,
      classSectionName: existing.classSectionName,
      periodNumber: existing.periodNumber,
      subjectName: existing.subjectName,
      teacherId: existing.teacherId,
      teacherName: existing.teacherName,
      reportDate: existing.reportDate,
      topicTaught: existing.topicTaught,
      homework: existing.homework,
      remarks: existing.remarks,
      reviewedBy: 99,
      reviewedByName: 'Rohit HOD',
      reviewedAt: '2026-09-09T10:00:00Z',
      status: ReportStatus.reviewed,
      reviewNote: note ?? existing.reviewNote,
    );
    reports = [for (final r in reports) r.id == reportId ? updated : r];
    return updated;
  }

  @override
  Future<TeachingReport> sendBack(int reportId, {required String note}) async {
    if (failSendBackWith != null) throw failSendBackWith!;
    lastSendBackNote = note;
    return _replace(reportId, status: ReportStatus.returned, note: note, returnedBy: 'Rohit HOD');
  }

  @override
  Future<TeachingReport> resubmit(
    int reportId, {
    required String topicTaught,
    String? homework,
    String? remarks,
  }) async {
    if (failResubmitWith != null) throw failResubmitWith!;
    lastResubmit = {'topic_taught': topicTaught, 'homework': homework, 'remarks': remarks};
    return _replace(reportId, status: ReportStatus.awaitingReview, topic: topicTaught, homework: homework);
  }

  TeachingReport _replace(
    int id, {
    ReportStatus? status,
    String? note,
    String? returnedBy,
    String? topic,
    String? homework,
  }) {
    final existing = reports.firstWhere((r) => r.id == id);
    final updated = TeachingReport(
      id: existing.id,
      schoolId: existing.schoolId,
      timetableEntryId: existing.timetableEntryId,
      classSectionName: existing.classSectionName,
      periodNumber: existing.periodNumber,
      subjectName: existing.subjectName,
      teacherId: existing.teacherId,
      teacherName: existing.teacherName,
      reportDate: existing.reportDate,
      topicTaught: topic ?? existing.topicTaught,
      homework: homework ?? existing.homework,
      remarks: existing.remarks,
      reviewedBy: existing.reviewedBy,
      reviewedByName: existing.reviewedByName,
      reviewedAt: existing.reviewedAt,
      syllabusTopicName: existing.syllabusTopicName,
      status: status ?? existing.status,
      reviewNote: note ?? existing.reviewNote,
      returnedAt: status == ReportStatus.returned ? '2026-10-26T06:00:00Z' : null,
      returnedByName: returnedBy ?? existing.returnedByName,
    );
    reports = [for (final r in reports) r.id == id ? updated : r];
    return updated;
  }
}
