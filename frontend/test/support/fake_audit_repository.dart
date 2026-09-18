import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/audit/data/models/audit_entry.dart';
import 'package:edutrack_app/features/audit/data/audit_log_repository.dart';

import 'fake_pagination.dart';

/// Test double for [AuditLogRepository] - pages [entries] the way the API
/// would and records the filters each call was made with.
class FakeAuditRepository implements AuditLogRepository {
  FakeAuditRepository({this.entries = const [], this.failListWith, this.failDownloadWith});

  List<AuditEntry> entries;
  Failure? failListWith;
  Failure? failDownloadWith;

  int listCalls = 0;
  int? lastSchoolId;
  String? lastModule;
  String? lastFrom;
  String? lastTo;

  int downloadCalls = 0;
  Map<String, Object?>? lastDownloadFilters;

  @override
  Future<PaginatedResponse<AuditEntry>> list({
    int? schoolId,
    String? module,
    String? from,
    String? to,
    required int page,
    required int perPage,
  }) async {
    listCalls++;
    lastSchoolId = schoolId;
    lastModule = module;
    lastFrom = from;
    lastTo = to;
    if (failListWith != null) throw failListWith!;

    return paginateFake(entries, page: page, perPage: perPage);
  }

  @override
  Future<List<int>> downloadCsv({int? schoolId, String? module, String? from, String? to}) async {
    downloadCalls++;
    lastDownloadFilters = {'school_id': schoolId, 'module': module, 'from': from, 'to': to};
    if (failDownloadWith != null) throw failDownloadWith!;

    return 'id,action\n1,student.updated\n'.codeUnits;
  }
}

/// A deterministic entry; override only what a test is about.
AuditEntry auditEntry({
  int id = 1,
  String? createdAtLabel = '09/16/2026 3:53 PM',
  int? schoolId = 1,
  String? schoolName = 'Green Valley School',
  int? userId = 7,
  String? userName = 'Anita Sharma',
  String? userRole = 'SCHOOL_ADMIN',
  String module = 'students',
  String action = 'student.updated',
  String entityType = 'student',
  int? entityId = 42,
  Map<String, dynamic>? oldValues = const {'first_name': 'Arjun', 'section': '8A'},
  Map<String, dynamic>? newValues = const {'first_name': 'Arjun K', 'section': '8B'},
  String? ip = '10.0.0.5',
}) {
  return AuditEntry(
    id: id,
    createdAt: DateTime.utc(2026, 9, 16, 10, 23, 45),
    createdAtLabel: createdAtLabel,
    schoolId: schoolId,
    schoolName: schoolName,
    userId: userId,
    userName: userName,
    userRole: userRole,
    module: module,
    action: action,
    entityType: entityType,
    entityId: entityId,
    oldValues: oldValues,
    newValues: newValues,
    ip: ip,
  );
}
