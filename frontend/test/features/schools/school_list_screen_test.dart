import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/school_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  logoUrl: null,
  status: SchoolStatus.active,
);

Widget wrap(FakeSchoolRepository fake) {
  return ProviderScope(
    overrides: [schoolRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(theme: AppTheme.light(), home: const SchoolListScreen()),
  );
}

void main() {
  testWidgets('shows an empty state when there are no schools', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No schools yet.'), findsOneWidget);
  });

  testWidgets('shows each school on the mobile layout', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school])));
    await tester.pumpAndSettle();

    expect(find.text('Sunrise Public School'), findsOneWidget);
    expect(find.textContaining('New Delhi, India'), findsOneWidget);
  });

  testWidgets('deactivating a school updates its status badge', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolRepository(schools: [_school])));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Inactive'), findsOneWidget);
  });
}
