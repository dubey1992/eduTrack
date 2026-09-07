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

Widget wrap({required UserRole actorRole}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: AuthenticatedUser(
            id: 99,
            name: 'Actor',
            email: 'actor@example.com',
            role: actorRole,
          ),
        ),
      ),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: [_school])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AddUserDialog()),
    ),
  );
}

void main() {
  testWidgets('a super admin sees a school picker for a non-super-admin role', (tester) async {
    await tester.pumpWidget(wrap(actorRole: UserRole.superAdmin));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(DropdownButtonFormField<int>, 'School'), findsOneWidget);
  });

  testWidgets('a school admin does not see a school picker (implicit own school)', (tester) async {
    await tester.pumpWidget(wrap(actorRole: UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(DropdownButtonFormField<int>, 'School'), findsNothing);
  });

  testWidgets('a school admin only sees operational roles in the role dropdown', (tester) async {
    await tester.pumpWidget(wrap(actorRole: UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<UserRole>, 'Role'));
    await tester.pumpAndSettle();

    expect(find.text('Super Admin').hitTestable(), findsNothing);
    expect(find.text('School Admin').hitTestable(), findsNothing);
    expect(find.text('Teacher').hitTestable(), findsWidgets);
  });
}
