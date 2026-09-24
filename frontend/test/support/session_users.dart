import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';

/// A signed-in user for tests. With neither map given the session carries no
/// permissions - the way every fixture written before the matrix existed
/// reads - and behaves as the platform defaults for its role (see
/// ModuleAccess). Pass [permissions] and/or [modules] to test the matrix and
/// the school's module switches.
AuthenticatedUser sessionUser(
  UserRole role, {
  int id = 1,
  String name = 'Actor',
  String email = 'actor@example.com',
  Map<String, PermissionLevel>? permissions,
  Map<String, bool> modules = const {},
  bool managesBranches = false,
}) {
  return AuthenticatedUser(
    id: id,
    name: name,
    email: email,
    role: role,
    managesBranches: managesBranches,
    access: ModuleAccess(permissions: permissions, modules: modules),
  );
}

/// Every module at [level] - what a Super Admin's payload looks like, or a
/// role the matrix has been raised on everywhere.
Map<String, PermissionLevel> allModulesAt(PermissionLevel level) => {for (final module in allModules) module: level};

/// Every module the matrix governs, in the order the backend lists them.
const allModules = [
  AppModules.students,
  AppModules.staff,
  AppModules.academics,
  AppModules.assessments,
  AppModules.attendance,
  AppModules.staffAttendance,
  AppModules.leave,
  AppModules.timetable,
  AppModules.teachingReports,
  AppModules.syllabus,
  AppModules.hod,
  AppModules.transport,
  AppModules.communication,
  AppModules.announcements,
  AppModules.payroll,
  AppModules.reports,
];
