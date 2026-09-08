import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/sidebar_nav.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';

Widget wrap(UserRole role) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: AuthenticatedUser(id: 1, name: 'Actor', email: 'actor@example.com', role: role),
        ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: SidebarNav()),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('a super admin sees Schools, Payments and Users', (tester) async {
    await tester.pumpWidget(wrap(UserRole.superAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Schools'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
  });

  testWidgets('a school admin sees Users but not Schools or Payments', (tester) async {
    await tester.pumpWidget(wrap(UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Schools'), findsNothing);
    expect(find.text('Payments'), findsNothing);
  });

  testWidgets('a teacher sees only the Dashboard entry', (tester) async {
    await tester.pumpWidget(wrap(UserRole.teacher));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Users'), findsNothing);
    expect(find.text('Schools'), findsNothing);
    expect(find.text('Payments'), findsNothing);
  });
}
