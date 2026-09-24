import 'permission_level.dart';
import 'user_role.dart';

/// The module keys the API uses in `permissions` and `modules` - the
/// registry in the backend's school/modules.py. Admin users, the audit log
/// and the platform's own business (schools, payments, mail settings, early
/// access) are not modules a role is granted: their screens stay role-gated.
abstract final class AppModules {
  static const students = 'students';
  static const staff = 'staff';
  static const academics = 'academics';
  static const assessments = 'assessments';
  static const attendance = 'attendance';
  static const staffAttendance = 'staff_attendance';
  static const leave = 'leave';
  static const timetable = 'timetable';
  static const teachingReports = 'teaching_reports';
  static const syllabus = 'syllabus';
  static const hod = 'hod';
  static const transport = 'transport';
  static const communication = 'communication';
  static const announcements = 'announcements';
  static const payroll = 'payroll';
  static const reports = 'reports';
}

/// What one signed-in account may see and do, module by module: the
/// `permissions` map (module -> level) and the `modules` map (module -> on
/// for their school) that /me and the sign-in response carry. See
/// docs/settings.md.
///
/// A payload that carries no `permissions` at all - an older API response, or
/// a test fixture built with just a role - is read against the platform's
/// default matrix ([defaultLevel]), which is exactly what every policy allowed
/// before the matrix existed. That keeps a role-only session behaving as it
/// always did rather than locking it out of everything, and keeps the
/// hundreds of role-only fixtures in the tests meaningful. A key missing from
/// a map that *is* present means none: the server lists every module.
class ModuleAccess {
  const ModuleAccess({this.permissions, this.modules = const {}});

  /// A session that said nothing about permissions or modules.
  const ModuleAccess.unspecified() : this();

  /// Reads the two maps off a user payload; either may be absent.
  factory ModuleAccess.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'];
    final modules = json['modules'];

    return ModuleAccess(
      permissions: permissions is Map
          ? permissions.map((key, value) => MapEntry(key.toString(), PermissionLevel.fromApiValue(value as String)))
          : null,
      modules: modules is Map ? modules.map((key, value) => MapEntry(key.toString(), value == true)) : const {},
    );
  }

  /// Module -> level, or null when the payload did not carry the map.
  final Map<String, PermissionLevel>? permissions;

  /// Module -> switched on for this user's school. A module not listed is on:
  /// the ones that cannot be switched off are never listed as off, and an
  /// older payload lists nothing.
  final Map<String, bool> modules;

  /// Whether the server told us the levels, or we are falling back to the
  /// platform defaults.
  bool get hasPermissions => permissions != null;

  bool moduleOn(String module) => modules[module] ?? true;

  /// The level [role] has on [module]. A Super Admin is always manage, as on
  /// the server, whatever the map says.
  PermissionLevel level(String module, UserRole role) {
    if (role == UserRole.superAdmin) return PermissionLevel.manage;

    final known = permissions;
    if (known != null) return known[module] ?? PermissionLevel.none;

    return defaultLevel(module, role);
  }

  /// Reading the module: it is on for the school, and the level is view or
  /// manage.
  bool canView(String module, UserRole role) => moduleOn(module) && level(module, role).atLeast(PermissionLevel.view);

  /// Writing in the module: it is on for the school, and the level is manage.
  /// A switched-off module refuses even a Super Admin, as the API does.
  bool canManage(String module, UserRole role) => moduleOn(module) && level(module, role) == PermissionLevel.manage;

  /// The platform's default matrix - module -> (School Admin, HOD, Teacher,
  /// Staff, Transport Manager, Accountant). A copy of the backend's
  /// permissions._DEFAULT_ROWS; a Group Admin follows the School Admin
  /// column, as it does everywhere else.
  static PermissionLevel defaultLevel(String module, UserRole role) {
    final row = _defaultRows[module];
    if (row == null) return PermissionLevel.none;

    return switch (role) {
      UserRole.superAdmin => PermissionLevel.manage,
      UserRole.schoolAdmin || UserRole.groupAdmin => row[0],
      UserRole.hod => row[1],
      UserRole.teacher => row[2],
      UserRole.staff => row[3],
      UserRole.transportManager => row[4],
      UserRole.accountant => row[5],
      UserRole.busAttendant => row[6],
    };
  }

  static const _none = PermissionLevel.none;
  static const _view = PermissionLevel.view;
  static const _manage = PermissionLevel.manage;

  static const _defaultRows = <String, List<PermissionLevel>>{
    AppModules.students: [_manage, _none, _view, _none, _none, _none, _none],
    AppModules.staff: [_manage, _none, _none, _none, _none, _none, _none],
    AppModules.academics: [_manage, _view, _view, _view, _view, _view, _none],
    AppModules.assessments: [_manage, _manage, _manage, _none, _none, _none, _none],
    AppModules.attendance: [_manage, _none, _manage, _none, _none, _none, _none],
    AppModules.staffAttendance: [_manage, _manage, _none, _none, _none, _none, _none],
    AppModules.leave: [_manage, _manage, _manage, _manage, _manage, _manage, _manage],
    AppModules.timetable: [_manage, _view, _view, _view, _view, _view, _none],
    AppModules.teachingReports: [_manage, _manage, _manage, _none, _none, _none, _none],
    AppModules.syllabus: [_manage, _manage, _manage, _none, _none, _none, _none],
    AppModules.hod: [_view, _view, _none, _none, _none, _none, _none],
    AppModules.transport: [_manage, _view, _view, _none, _manage, _none, _manage],
    AppModules.communication: [_manage, _none, _none, _none, _none, _none, _none],
    AppModules.announcements: [_manage, _manage, _none, _none, _none, _none, _none],
    AppModules.payroll: [_manage, _none, _none, _none, _none, _manage, _none],
    AppModules.reports: [_view, _view, _none, _none, _view, _view, _none],
  };
}
