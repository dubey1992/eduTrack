import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/session_users.dart';

/// What /me sends for a teacher whose school has switched attendance off.
Map<String, dynamic> _teacherJson({Map<String, dynamic>? permissions, Map<String, dynamic>? modules}) => {
  'id': 7,
  'name': 'Priya Nair',
  'email': 'priya@example.test',
  'role': 'TEACHER',
  'permissions': ?permissions,
  'modules': ?modules,
};

void main() {
  group('PermissionLevel', () {
    test('manage includes view, view includes none, none includes nothing else', () {
      expect(PermissionLevel.manage.atLeast(PermissionLevel.view), isTrue);
      expect(PermissionLevel.manage.atLeast(PermissionLevel.manage), isTrue);
      expect(PermissionLevel.view.atLeast(PermissionLevel.manage), isFalse);
      expect(PermissionLevel.view.atLeast(PermissionLevel.view), isTrue);
      expect(PermissionLevel.none.atLeast(PermissionLevel.view), isFalse);
      expect(PermissionLevel.none.atLeast(PermissionLevel.none), isTrue);
    });

    test('maps to and from the API words', () {
      for (final level in PermissionLevel.values) {
        expect(PermissionLevel.fromApiValue(level.apiValue), level);
      }
      expect(() => PermissionLevel.fromApiValue('admin'), throwsArgumentError);
    });
  });

  group('a session carrying both maps', () {
    final user = AuthenticatedUser.fromJson(
      _teacherJson(
        permissions: {'students': 'view', 'attendance': 'manage', 'staff': 'none'},
        modules: {'students': true, 'attendance': false, 'payroll': true},
      ),
    );

    test('reads each level as sent', () {
      expect(user.level(AppModules.students), PermissionLevel.view);
      expect(user.level(AppModules.attendance), PermissionLevel.manage);
      expect(user.level(AppModules.staff), PermissionLevel.none);
    });

    test('a module the map does not name is none - the server lists every module', () {
      expect(user.level(AppModules.payroll), PermissionLevel.none);
      expect(user.canView(AppModules.payroll), isFalse);
    });

    test('view is not manage', () {
      expect(user.canView(AppModules.students), isTrue);
      expect(user.canManage(AppModules.students), isFalse);
    });

    test('a switched-off module is neither viewable nor manageable, whatever the level', () {
      expect(user.moduleOn(AppModules.attendance), isFalse);
      expect(user.canView(AppModules.attendance), isFalse);
      expect(user.canManage(AppModules.attendance), isFalse);
    });

    test('a module the switches do not name is on', () {
      // The spine (students, staff, academics) is never switched off, and
      // the server only lists what it knows about.
      expect(user.moduleOn(AppModules.academics), isTrue);
      expect(user.moduleOn('something_new'), isTrue);
    });
  });

  group('a session carrying no maps', () {
    // Older API responses and every role-only fixture in the tests.
    final teacher = AuthenticatedUser.fromJson(_teacherJson());

    test('says so', () {
      expect(teacher.access.hasPermissions, isFalse);
      expect(teacher.access.modules, isEmpty);
    });

    test('behaves as the platform defaults for its role', () {
      expect(teacher.level(AppModules.students), PermissionLevel.view);
      expect(teacher.level(AppModules.attendance), PermissionLevel.manage);
      expect(teacher.level(AppModules.staff), PermissionLevel.none);
      expect(teacher.canManage(AppModules.attendance), isTrue);
      expect(teacher.canManage(AppModules.students), isFalse);
      expect(teacher.canView(AppModules.staff), isFalse);
    });

    test('every module is on', () {
      expect(teacher.moduleOn(AppModules.attendance), isTrue);
      expect(teacher.moduleOn(AppModules.payroll), isTrue);
    });

    test('a module that is not in the matrix is none', () {
      expect(teacher.level('users'), PermissionLevel.none);
      expect(ModuleAccess.defaultLevel('audit', UserRole.schoolAdmin), PermissionLevel.none);
    });
  });

  group('the default matrix', () {
    test('matches docs/settings.md row by row', () {
      PermissionLevel at(String module, UserRole role) => ModuleAccess.defaultLevel(module, role);

      expect(at(AppModules.students, UserRole.schoolAdmin), PermissionLevel.manage);
      expect(at(AppModules.students, UserRole.hod), PermissionLevel.none);
      expect(at(AppModules.staffAttendance, UserRole.hod), PermissionLevel.manage);
      expect(at(AppModules.leave, UserRole.staff), PermissionLevel.manage);
      expect(at(AppModules.timetable, UserRole.accountant), PermissionLevel.view);
      expect(at(AppModules.hod, UserRole.schoolAdmin), PermissionLevel.view);
      expect(at(AppModules.transport, UserRole.transportManager), PermissionLevel.manage);
      expect(at(AppModules.transport, UserRole.staff), PermissionLevel.none);
      expect(at(AppModules.communication, UserRole.hod), PermissionLevel.none);
      expect(at(AppModules.announcements, UserRole.hod), PermissionLevel.manage);
      expect(at(AppModules.payroll, UserRole.accountant), PermissionLevel.manage);
      expect(at(AppModules.payroll, UserRole.teacher), PermissionLevel.none);
      expect(at(AppModules.reports, UserRole.staff), PermissionLevel.none);
    });

    test('a group admin follows the school admin row', () {
      for (final module in allModules) {
        expect(
          ModuleAccess.defaultLevel(module, UserRole.groupAdmin),
          ModuleAccess.defaultLevel(module, UserRole.schoolAdmin),
          reason: module,
        );
      }
    });
  });

  group('a super admin', () {
    test('is manage everywhere, with or without a map', () {
      final bare = sessionUser(UserRole.superAdmin);
      final sentNone = sessionUser(UserRole.superAdmin, permissions: allModulesAt(PermissionLevel.none));

      for (final module in allModules) {
        expect(bare.canManage(module), isTrue, reason: module);
        expect(sentNone.canManage(module), isTrue, reason: module);
      }
    });

    test('still cannot use a module the school has switched off', () {
      final user = sessionUser(UserRole.superAdmin, modules: {AppModules.payroll: false});

      expect(user.level(AppModules.payroll), PermissionLevel.manage);
      expect(user.canView(AppModules.payroll), isFalse);
      expect(user.canManage(AppModules.payroll), isFalse);
    });
  });

  group('an admin-users row', () {
    // The same payload serves the list and /me, so a row carries the maps too.
    final json = {
      'id': 3,
      'first_name': 'Anita',
      'last_name': 'Rao',
      'name': 'Anita Rao',
      'email': 'anita@example.test',
      'mobile': null,
      'role': 'SCHOOL_ADMIN',
      'status': 'active',
      'permissions': {'students': 'manage', 'payroll': 'none'},
      'modules': {'payroll': false},
    };

    test('parses its permissions and switches', () {
      final user = AppUser.fromJson(json);

      expect(user.canManage(AppModules.students), isTrue);
      expect(user.level(AppModules.payroll), PermissionLevel.none);
      expect(user.moduleOn(AppModules.payroll), isFalse);
      expect(user.canView(AppModules.staff), isFalse);
    });

    test('keeps them through copyWith', () {
      final user = AppUser.fromJson(json).copyWith(status: UserStatus.inactive);

      expect(user.status, UserStatus.inactive);
      expect(user.canManage(AppModules.students), isTrue);
      expect(user.moduleOn(AppModules.payroll), isFalse);
    });

    test('without the maps reads as the defaults for its role', () {
      final user = AppUser.fromJson(
        {...json}
          ..remove('permissions')
          ..remove('modules'),
      );

      expect(user.access.hasPermissions, isFalse);
      expect(user.canManage(AppModules.students), isTrue);
      expect(user.canManage(AppModules.payroll), isTrue);
    });
  });
}
