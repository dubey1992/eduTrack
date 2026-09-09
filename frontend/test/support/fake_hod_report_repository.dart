import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/hod/data/hod_report_repository.dart';
import 'package:edutrack_app/features/hod/data/models/hod_department_report.dart';

class FakeHodReportRepository implements HodReportRepository {
  FakeHodReportRepository({required this.report, this.failWith});

  HodDepartmentReport report;
  Failure? failWith;

  /// The last query the screen/notifier asked for, so tests can assert
  /// what was sent (month, page, filters) rather than only what came back.
  Map<String, Object?>? lastRequest;
  int callCount = 0;

  @override
  Future<HodDepartmentReport> departmentReport({
    int? schoolId,
    int? departmentId,
    required String month,
    required int page,
    required int perPage,
  }) async {
    callCount++;
    lastRequest = {
      'school_id': schoolId,
      'department_id': departmentId,
      'month': month,
      'page': page,
      'per_page': perPage,
    };
    if (failWith != null) throw failWith!;
    return report;
  }
}
