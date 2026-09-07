import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/routing/app_router.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:edutrack_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_user_repository.dart';

const _superAdmin = AuthenticatedUser(
  id: 1,
  name: 'Super Admin',
  email: 'admin@example.com',
  role: UserRole.superAdmin,
);

const _teacher = AuthenticatedUser(
  id: 2,
  name: 'A Teacher',
  email: 'teacher@example.com',
  role: UserRole.teacher,
);

void main() {
  testWidgets('a super admin sees the Manage Users entry point on the dashboard', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _superAdmin)),
        ],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage Users'), findsOneWidget);
  });

  testWidgets('a non-super-admin does not see the Manage Users entry point', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher))],
        child: const EduTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage Users'), findsNothing);
  });

  testWidgets('a non-super-admin is redirected away from /users back to the dashboard', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _teacher)),
        userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const EduTrackApp()));
    await tester.pumpAndSettle();

    // Navigate the router directly to /users; the redirect should bounce it
    // straight back to the dashboard for a non-SUPER_ADMIN user.
    container.read(routerProvider).go('/users');
    await tester.pumpAndSettle();

    expect(find.text('Users'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
  });
}
