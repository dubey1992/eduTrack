import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/school_filter_dropdown.dart';
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

Widget wrap({required UserRole role, int? selected, required ValueChanged<int?> onChanged}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: AuthenticatedUser(id: 1, name: 'Actor', email: 'actor@example.com', role: role),
        ),
      ),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: [_school])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SchoolFilterDropdown(selected: selected, onChanged: onChanged),
      ),
    ),
  );
}

void main() {
  testWidgets('renders nothing for a non-super-admin role', (tester) async {
    await tester.pumpWidget(wrap(role: UserRole.schoolAdmin, onChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
  });

  testWidgets('shows an "All Schools" option plus every active school for a super admin', (tester) async {
    await tester.pumpWidget(wrap(role: UserRole.superAdmin, onChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();

    expect(find.text('All Schools').hitTestable(), findsOneWidget);
    expect(find.text('Sunrise Public School').hitTestable(), findsOneWidget);
  });

  testWidgets('selecting a school calls onChanged with its id', (tester) async {
    int? selectedId = -1;
    await tester.pumpWidget(wrap(role: UserRole.superAdmin, onChanged: (id) => selectedId = id));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunrise Public School').last);
    await tester.pumpAndSettle();

    expect(selectedId, 1);
  });
}
