import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:edutrack_app/features/users/presentation/user_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_user_repository.dart';

const _teacher = AppUser(
  id: 1,
  firstName: 'Priya',
  lastName: 'Sharma',
  name: 'Priya Sharma',
  email: 'priya@example.com',
  mobile: '9876543210',
  role: UserRole.teacher,
  status: UserStatus.active,
);

Widget wrap(FakeUserRepository fake) {
  return ProviderScope(
    overrides: [userRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(theme: AppTheme.light(), home: const UserListScreen()),
  );
}

void main() {
  testWidgets('shows an empty state when there are no users', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No users yet.'), findsOneWidget);
  });

  testWidgets('shows each user on the mobile layout', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(users: [_teacher])));
    await tester.pumpAndSettle();

    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.textContaining('priya@example.com'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
  });

  testWidgets('shows a data table on the desktop layout', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(FakeUserRepository(users: [_teacher])));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('deactivating a user updates their status badge', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(FakeUserRepository(users: [_teacher])));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);
  });
}
