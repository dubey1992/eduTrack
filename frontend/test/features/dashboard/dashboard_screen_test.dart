import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

Widget wrap() {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: const AuthenticatedUser(
            id: 1,
            name: 'Admin',
            email: 'admin@example.com',
            role: UserRole.superAdmin,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: DashboardScreen()),
    ),
  );
}

void main() {
  testWidgets('quick action cards are the same height regardless of subtitle length', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // "Record Payment"'s subtitle is two lines, "Manage Schools"'s is one -
    // the fixed-height fix means both cards report the same render height.
    final schoolsCardHeight = tester
        .getSize(find.ancestor(of: find.text('Manage Schools'), matching: find.byType(SizedBox)).first)
        .height;
    final paymentCardHeight = tester
        .getSize(find.ancestor(of: find.text('Record Payment'), matching: find.byType(SizedBox)).first)
        .height;

    expect(schoolsCardHeight, paymentCardHeight);
  });

  testWidgets('a long subtitle is truncated rather than overflowing the card', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final subtitle = tester.widget<Text>(find.text('Log a payment received from a school'));
    expect(subtitle.maxLines, 2);
    expect(subtitle.overflow, TextOverflow.ellipsis);
  });
}
