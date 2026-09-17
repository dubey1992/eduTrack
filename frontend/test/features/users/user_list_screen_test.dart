import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:edutrack_app/features/users/presentation/user_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_user_repository.dart';
import '../../support/paginated_table.dart';

const _superAdmin = AuthenticatedUser(id: 99, name: 'Actor', email: 'actor@example.com', role: UserRole.superAdmin);
const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);
const _subAdmin = AuthenticatedUser(
  id: 6,
  name: 'Sub Admin',
  email: 'subadmin@example.com',
  role: UserRole.schoolAdmin,
  isSubAdmin: true,
);

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

const _subAdminRow = AppUser(
  id: 2,
  firstName: 'Rahul',
  lastName: 'Verma',
  name: 'Rahul Verma',
  email: 'rahul@example.com',
  mobile: null,
  role: UserRole.schoolAdmin,
  status: UserStatus.active,
  isSubAdmin: true,
);

const _peerAdminRow = AppUser(
  id: 3,
  firstName: 'Kavita',
  lastName: 'Nair',
  name: 'Kavita Nair',
  email: 'kavita@example.com',
  mobile: null,
  role: UserRole.schoolAdmin,
  status: UserStatus.active,
);

Widget wrap(FakeUserRepository fake, {AuthenticatedUser actor = _superAdmin}) {
  return ProviderScope(
    overrides: [
      userRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: UserListScreen()),
    ),
  );
}

void main() {
  testWidgets('a super admin sees the Add School Admin action', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Add School Admin'), findsOneWidget);
  });

  testWidgets('a (non-sub) school admin sees the Add Sub Admin action instead', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(), actor: _schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Add School Admin'), findsNothing);
    expect(find.text('Add Sub Admin'), findsOneWidget);
  });

  testWidgets('a sub admin sees no add-admin action at all', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(), actor: _subAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Add School Admin'), findsNothing);
    expect(find.text('Add Sub Admin'), findsNothing);
  });

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

  testWidgets('shows Sub Admin instead of School Admin for a sub-admin row', (tester) async {
    // Desktop layout puts the role in its own DataCell rather than
    // combined into one Text with the email (as the mobile ListTile
    // subtitle does), so it can be matched exactly without colliding with
    // the "Add School Admin" button text.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(FakeUserRepository(users: [_subAdminRow])));
    await tester.pumpAndSettle();

    expect(find.text('Rahul Verma'), findsOneWidget);
    expect(find.text('Sub Admin'), findsOneWidget);
    expect(find.text('School Admin'), findsNothing);
  });

  testWidgets('a (non-sub) school admin sees Edit/Deactivate actions on a sub-admin row', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(users: [_subAdminRow]), actor: _schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Rahul Verma'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
  });

  testWidgets('a school admin sees no Edit/Deactivate actions on a peer (non-sub) school admin row', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(users: [_peerAdminRow]), actor: _schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Kavita Nair'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('Deactivate'), findsNothing);
  });

  testWidgets('a sub admin sees no Edit/Deactivate actions on any admin-tier row', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(users: [_subAdminRow]), actor: _subAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Rahul Verma'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('Deactivate'), findsNothing);
  });

  testWidgets('a super admin still sees Edit/Deactivate actions on a sub-admin row', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(users: [_subAdminRow])));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
  });

  testWidgets('a school admin still sees Edit/Deactivate actions on a non-admin row', (tester) async {
    await tester.pumpWidget(wrap(FakeUserRepository(users: [_teacher]), actor: _schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
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

  testWidgets('a full page of users scrolls above the pagination bar on desktop', (tester) async {
    useShortDesktopWindow(tester);
    final users = [
      for (var n = 1; n <= 20; n++)
        AppUser(
          id: n,
          firstName: 'User',
          lastName: 'Number $n',
          name: 'User Number $n',
          email: 'user$n@example.com',
          mobile: null,
          role: UserRole.teacher,
          status: UserStatus.active,
        ),
    ];
    await tester.pumpWidget(wrap(FakeUserRepository(users: users)));
    await tester.pumpAndSettle();

    await expectLastRowScrollsAbovePagination(tester, find.text('User Number 20'));
  });
}
