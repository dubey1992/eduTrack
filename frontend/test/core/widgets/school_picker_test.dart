import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/school_picker.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';

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

/// The one picker every form and filter uses to ask which school a record
/// belongs to. It was twelve identical private copies until the wording had to
/// differ by who is looking, at which point twelve places to change was twelve
/// chances to miss one.
void main() {
  final formKey = GlobalKey<FormState>();

  Widget wrap({required UserRole role, bool required = true}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            sessionOnRestore: AuthenticatedUser(
              id: 1,
              name: 'Actor',
              email: 'actor@example.com',
              role: role,
              managesBranches: role != UserRole.superAdmin,
            ),
          ),
        ),
        schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: [_school])),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Form(
            key: formKey,
            child: SchoolPicker(selected: null, onChanged: (_) {}, required: required),
          ),
        ),
      ),
    );
  }

  testWidgets('a super admin is picking a school', (tester) async {
    await tester.pumpWidget(wrap(role: UserRole.superAdmin));
    await tester.pumpAndSettle();

    expect(find.text('School'), findsOneWidget);
    expect(find.text('Branch'), findsNothing);
  });

  testWidgets('an admin in a group is picking a branch', (tester) async {
    // Same list, same record - the word just says what they are choosing
    // between, matching the filter above it on the same screen.
    await tester.pumpWidget(wrap(role: UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Branch'), findsOneWidget);
    expect(find.text('School'), findsNothing);
  });

  testWidgets('a group admin gets the branch wording too', (tester) async {
    await tester.pumpWidget(wrap(role: UserRole.groupAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Branch'), findsOneWidget);
  });

  testWidgets('it lists every active school it was given', (tester) async {
    await tester.pumpWidget(wrap(role: UserRole.superAdmin));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();

    expect(find.text('Sunrise Public School').hitTestable(), findsOneWidget);
  });

  testWidgets('on a form, leaving it unanswered is an error in its own words', (tester) async {
    await tester.pumpWidget(wrap(role: UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pumpAndSettle();

    // The message follows the label: a grouped admin is not told to pick a
    // "school" by a field labelled Branch.
    expect(find.text('Branch is required'), findsOneWidget);
  });

  testWidgets('on a filter, leaving it unanswered means all of them', (tester) async {
    await tester.pumpWidget(wrap(role: UserRole.schoolAdmin, required: false));
    await tester.pumpAndSettle();

    expect(formKey.currentState!.validate(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('Branch is required'), findsNothing);
  });
}
