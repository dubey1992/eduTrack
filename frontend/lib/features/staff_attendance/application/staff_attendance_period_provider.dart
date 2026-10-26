import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reports/data/models/report.dart';
import '../../reports/data/report_repository.dart';

/// Which staff, over which days: the school (for a Super Admin; null means
/// the actor's own), an optional department, and an inclusive date range.
typedef StaffAttendancePeriodParams = ({int? schoolId, int? departmentId, String from, String to});

/// Each person's totals over a week or a month (docs/teacher-app.md,
/// "Filters by period"), from the same staff attendance report the Reports
/// screen prints; the server narrows it to an HOD's own departments.
final staffAttendancePeriodProvider = FutureProvider.autoDispose.family<ReportResult, StaffAttendancePeriodParams>(
  (ref, params) => ref
      .read(reportRepositoryProvider)
      .fetch(
        ReportKind.staffAttendance,
        schoolId: params.schoolId,
        departmentId: params.departmentId,
        from: params.from,
        to: params.to,
      ),
  retry: (retryCount, error) => null,
);
