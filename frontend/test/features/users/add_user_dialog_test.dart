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
}
