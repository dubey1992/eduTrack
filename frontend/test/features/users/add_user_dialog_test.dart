import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:edutrack_app/features/users/presentation/add_user_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_user_repository.dart';

const _superAdmin = AuthenticatedUser(id: 99, name: 'Actor', email: 'actor@example.com', role: UserRole.superAdmin);
const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

const _school = School(
  id: 1,
  name: 'Sunrise Public School',
  registrationNumber: null,
  email: 'admin@sunriseschool.edu',
  phone: '+91 98765 43210',
  address: '12 School Road',
  city: 'New Delhi',
  state: 'Delhi',
  country: 'India',
  postalCode: '110001',
  currencyCode: 'INR',
  timezone: 'UTC',
  logoUrl: null,
  status: SchoolStatus.active,
);

const _closedSchool = School(
  id: 2,
  name: 'Closed Down Academy',
  registrationNumber: null,
  email: 'admin@closeddown.edu',
  phone: '+91 98765 00000',
  address: '9 Old Road',
  city: 'Mumbai',
  state: 'Maharashtra',
  country: 'India',
  postalCode: '400001',
  currencyCode: 'INR',
  timezone: 'UTC',
  logoUrl: null,
  status: SchoolStatus.inactive,
);

Widget wrap({AuthenticatedUser actor = _superAdmin, List<School> schools = const [_school]}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: schools)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AddUserDialog()),
    ),
  );
}

/// Opens the dialog from a button, so that saving can close it the way it
/// does in the app and the confirmation lands on the page beneath.
Widget openable(FakeUserRepository users, {AuthenticatedUser actor = _schoolAdmin}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      userRepositoryProvider.overrideWithValue(users),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: const [_school])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const AddUserDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> openAndFill(WidgetTester tester, {String? password}) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'First name'), 'Priya');
  await tester.enterText(find.widgetWithText(TextFormField, 'Last name'), 'Nair');
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'priya@example.com');
  if (password != null) {
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
  }
}

/// This dialog only ever creates SCHOOL_ADMIN-role accounts (see
/// UserPolicy::create() and StoreUserRequest on the backend) - whether the
/// result reads as "School Admin" or "Sub Admin" depends on who's creating
/// it, not on anything picked in the form.
void main() {
  testWidgets('a super admin sees Add School Admin and must pick a school', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Add School Admin'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'School'), findsOneWidget);
  });

  testWidgets('a school admin sees Add Sub Admin with no school picker (implicit own school)', (tester) async {
    await tester.pumpWidget(wrap(actor: _schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Add Sub Admin'), findsOneWidget);
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'School'), findsNothing);
  });

  testWidgets('the school picker excludes deactivated schools', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(schools: [_school, _closedSchool]));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'School'));
    await tester.pumpAndSettle();

    expect(find.text('Sunrise Public School').hitTestable(), findsWidgets);
    expect(find.text('Closed Down Academy').hitTestable(), findsNothing);
  });

  group('the password', () {
    testWidgets('may be left blank, and then a link to set one is emailed', (tester) async {
      final users = FakeUserRepository();
      await tester.pumpWidget(openable(users));
      await openAndFill(tester);

      expect(find.textContaining('Leave blank to email them a link'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(users.createCalled, isTrue);
      expect(users.lastPassword, isNull);
      expect(find.byType(AddUserDialog), findsNothing);
      expect(
        find.text('Sub admin created. A link to set their password was emailed to priya@example.com.'),
        findsOneWidget,
      );
    });

    testWidgets('when typed, is sent as it is and no email is promised', (tester) async {
      final users = FakeUserRepository();
      await tester.pumpWidget(openable(users));
      await openAndFill(tester, password: 'AGoodPassword2026');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(users.lastPassword, 'AGoodPassword2026');
      expect(find.text('Sub admin created.'), findsOneWidget);
      expect(find.textContaining('emailed'), findsNothing);
    });

    testWidgets('when typed badly, is refused rather than dropped', (tester) async {
      final users = FakeUserRepository();
      await tester.pumpWidget(openable(users));
      await openAndFill(tester, password: 'short1');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(users.createCalled, isFalse);
      expect(find.byType(AddUserDialog), findsOneWidget);
    });
  });
}
