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

  Map<String, dynamic>? lastStorePayload;
  int? lastReviewedId;

  @override
  Future<TeachingReport> store({
    required int timetableEntryId,
    required String reportDate,
    required String topicTaught,
    String? homework,
    String? remarks,
  }) async {
    if (failStoreWith != null) throw failStoreWith!;
    lastStorePayload = {
      'timetable_entry_id': timetableEntryId,
      'report_date': reportDate,
      'topic_taught': topicTaught,
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
    required int page,
    required int perPage,
  }) async {
    final filtered = reports.where((r) {
      if (schoolId != null && r.schoolId != schoolId) return false;
      if (teacherId != null && r.teacherId != teacherId) return false;
      if (reportDate != null && r.reportDate != reportDate) return false;
      return true;
    }).toList();

    return PaginatedResponse(items: filtered, currentPage: page, lastPage: 1, total: filtered.length, perPage: perPage);
  }

  @override
  Future<TeachingReportSummary> summary({int? schoolId, required String date}) async {
    return summaryData;
  }

  @override
  Future<TeachingReport> review(int reportId) async {
    lastReviewedId = reportId;
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
    );
    reports = [for (final r in reports) r.id == reportId ? updated : r];
    return updated;
  }
}
