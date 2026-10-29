import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/session_users.dart';

/// The Messaging screen is the platform's own: only a Super Admin sees it,
/// whatever the matrix grants anybody else.
void main() {
  final item = AppNav.findByPath('/messaging-settings')!;

  test('sits right after Email Settings, with its own title', () {
    final paths = AppNav.administration.items.map((i) => i.path).toList();

    expect(paths.indexOf('/messaging-settings'), paths.indexOf('/mail-settings') + 1);
    expect(item.label, 'Messaging');
    expect(item.icon, Icons.sms_outlined);
    expect(item.pageTitle, 'Messaging');
    expect(item.module, isNull);
    expect(isAppRoute('/messaging-settings'), isTrue);
  });

  test('ALLOW: a Super Admin', () {
    expect(item.allows(sessionUser(UserRole.superAdmin)), isTrue);
  });

  test('DENY: every other role, even one the matrix gives everything', () {
    for (final role in UserRole.values.where((r) => r != UserRole.superAdmin)) {
      expect(item.allows(sessionUser(role)), isFalse, reason: role.label);
      expect(
        item.allows(sessionUser(role, permissions: allModulesAt(PermissionLevel.manage))),
        isFalse,
        reason: '${role.label} with every module at manage',
      );
    }
  });
}
