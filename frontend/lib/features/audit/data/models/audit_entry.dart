import 'dart:convert';

import '../../../../core/models/user_role.dart';
import '../../../../core/utils/date_format.dart';

/// The areas of the product that write to the audit trail. Mirrors the
/// `module` values the backend records - a filter offers exactly these.
enum AuditModule {
  academic('academic', 'Academic setup'),
  announcements('announcements', 'Announcements'),
  attendance('attendance', 'Student attendance'),
  auth('auth', 'Sign-in & security'),
  communication('communication', 'Communication'),
  holidays('holidays', 'Holidays'),
  leave('leave', 'Staff leave'),
  payments('payments', 'Payments'),
  payroll('payroll', 'Payroll'),
  schools('schools', 'Schools'),
  staff('staff', 'Teachers & staff'),
  staffAttendance('staff_attendance', 'Staff attendance'),
  students('students', 'Students'),
  syllabus('syllabus', 'Syllabus'),
  teaching('teaching', 'Teaching reports'),
  timetable('timetable', 'Timetable'),
  transport('transport', 'Transport'),
  users('users', 'Users');

  const AuditModule(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// The label for a module value from the API. A module the app does not
  /// know yet is still shown, just humanised, rather than failing the list.
  static String labelFor(String apiValue) {
    for (final module in values) {
      if (module.apiValue == apiValue) return module.label;
    }
    return humanize(apiValue);
  }
}

/// "student.updated" -> "Student updated", "first_name" -> "First name".
String humanize(String raw) {
  final words = raw.replaceAll(RegExp(r'[._]+'), ' ').trim().toLowerCase();
  if (words.isEmpty) return raw;

  return words[0].toUpperCase() + words.substring(1);
}

/// One row of the audit trail, as returned by `GET /audit-logs`.
///
/// Read-only by design: nothing in the app writes or edits these.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.createdAt,
    required this.createdAtLabel,
    required this.schoolId,
    required this.schoolName,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.module,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.oldValues,
    required this.newValues,
    required this.ip,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      id: json['id'] as int,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc(),
      createdAtLabel: json['created_at_label'] as String?,
      schoolId: json['school_id'] as int?,
      schoolName: json['school_name'] as String?,
      userId: json['user_id'] as int?,
      userName: json['user_name'] as String?,
      userRole: json['user_role'] as String?,
      module: json['module'] as String,
      action: json['action'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as int?,
      oldValues: _asMap(json['old_values']),
      newValues: _asMap(json['new_values']),
      ip: json['ip'] as String?,
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) => value is Map ? Map<String, dynamic>.from(value) : null;

  final int id;

  /// The UTC instant the change happened.
  final DateTime? createdAt;

  /// The same instant rendered by the server in the viewer's school timezone
  /// - the client has no timezone database, so this is what gets shown.
  final String? createdAtLabel;

  /// Null for platform-level entries (a Super Admin's own actions).
  final int? schoolId;
  final String? schoolName;
  final int? userId;
  final String? userName;
  final String? userRole;
  final String module;

  /// e.g. `student.updated`.
  final String action;

  /// e.g. `student`.
  final String entityType;
  final int? entityId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? ip;

  String get whenLabel {
    if (createdAtLabel != null && createdAtLabel!.isNotEmpty) return createdAtLabel!;
    // Only when the server sent no label: the raw instant, marked as UTC so
    // it is never mistaken for the school's time.
    return createdAt == null ? '-' : '${formatDateTime(createdAt!)} UTC';
  }

  String get moduleLabel => AuditModule.labelFor(module);

  String get actionLabel => humanize(action);

  String get recordLabel => entityId == null ? humanize(entityType) : '${humanize(entityType)} #$entityId';

  /// Who did it. A failed sign-in has no account behind it, so the address
  /// that was tried is the most useful thing to show.
  String get actorLabel {
    if (userName != null && userName!.isNotEmpty) return userName!;

    final attemptedEmail = newValues?['email'];
    if (action == 'user.sign_in_failed' && attemptedEmail is String && attemptedEmail.isNotEmpty) {
      return attemptedEmail;
    }

    return userId == null && action != 'user.sign_in_failed' ? 'System' : 'Unknown account';
  }

  /// The role the actor held, when there was an actor.
  String? get roleLabel {
    final role = userRole;
    if (role == null || role.isEmpty) return null;

    for (final value in UserRole.values) {
      if (value.apiValue == role) return value.label;
    }
    return humanize(role);
  }

  String get schoolLabel => schoolName ?? (schoolId == null ? 'Platform' : 'School #$schoolId');

  /// What changed, field by field. Empty when nothing was recorded.
  List<AuditChange> get changes {
    final before = oldValues ?? const <String, dynamic>{};
    final after = newValues ?? const <String, dynamic>{};
    final keys = <String>{...before.keys, ...after.keys};

    return [
      for (final key in keys)
        AuditChange(field: key, before: formatAuditValue(before[key]), after: formatAuditValue(after[key])),
    ];
  }

  /// Whether the entry records both sides of a change, or just one - a
  /// creation carries only new values, a deletion only old ones.
  AuditChangeShape get changeShape {
    final hasOld = oldValues != null && oldValues!.isNotEmpty;
    final hasNew = newValues != null && newValues!.isNotEmpty;

    if (hasOld && hasNew) return AuditChangeShape.beforeAndAfter;
    if (hasNew) return AuditChangeShape.afterOnly;
    if (hasOld) return AuditChangeShape.beforeOnly;
    return AuditChangeShape.none;
  }
}

enum AuditChangeShape { beforeAndAfter, afterOnly, beforeOnly, none }

class AuditChange {
  const AuditChange({required this.field, required this.before, required this.after});

  /// The raw key, e.g. `first_name`.
  final String field;
  final String before;
  final String after;

  String get fieldLabel => humanize(field);
}

/// A recorded value as text: "-" for nothing, compact JSON for anything
/// nested.
String formatAuditValue(Object? value) {
  if (value == null) return '-';
  if (value is String) return value.isEmpty ? '-' : value;
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is Map || value is List) return jsonEncode(value);
  return value.toString();
}
