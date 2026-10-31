import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/classes/presentation/quick_class_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_year_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';

const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

AcademicYear _year(int id, String name, {required bool current}) => AcademicYear(
  id: id,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: name,
  startDate: DateTime(2026, 4, 1),
  endDate: DateTime(2027, 3, 31),
  isCurrent: current,
);

Widget wrap(FakeSchoolClassRepository fake, {List<AcademicYear>? years}) {
  return ProviderScope(
    overrides: [
      schoolClassRepositoryProvider.overrideWithValue(fake),
      academicYearRepositoryProvider.overrideWithValue(
        FakeAcademicYearRepository(
          years: years ?? [_year(2, '2025-26', current: false), _year(3, '2026-27', current: true)],
        ),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const QuickClassSetupDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

FilterChip _chip(WidgetTester tester, String name) => tester.widget(find.widgetWithText(FilterChip, name));

void main() {
  testWidgets('opens on the current year with the default classes ticked', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository()));
    await _open(tester);

    expect(find.widgetWithText(DropdownButtonFormField<int>, '2026-27'), findsOneWidget);
    expect(_chip(tester, 'Playgroup').selected, isFalse);
    expect(_chip(tester, 'Nursery').selected, isTrue);
    expect(find.text('Create 4 classes'), findsOneWidget);
  });

  testWidgets('creates the ticked classes in class order with the chosen sections', (tester) async {
    final fake = FakeSchoolClassRepository();
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    // Untick, then tick again: it goes back in its class's place, not last.
    await tester.tap(find.widgetWithText(FilterChip, 'Nursery'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Nursery'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Sections in each class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 (A-C)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create 4 classes'));
    await tester.pumpAndSettle();

    expect(fake.quickSetupClasses, ['Nursery', 'LKG', 'UKG', 'Class 1']);
    expect(fake.quickSetupSections, 3);
    expect(find.byType(QuickClassSetupDialog), findsNothing);
    expect(find.text('Created 4 classes, each with sections A, B, C.'), findsOneWidget);
  });

  testWidgets('names the classes the year already had', (tester) async {
    final fake = FakeSchoolClassRepository(
      // A list the fake can add to.
      classes: [
        const SchoolClass(
          id: 1,
          schoolId: 1,
          schoolName: 'Sunrise Public School',
          academicYearId: 3,
          academicYearName: '2026-27',
          name: 'LKG',
          level: -1,
          sections: [],
        ),
      ],
    );
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await tester.tap(find.text('Create 4 classes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Created 3 classes'), findsOneWidget);
    expect(find.textContaining('Already there, left as they were: LKG.'), findsOneWidget);
  });

  testWidgets('nothing ticked is refused before anything is sent', (tester) async {
    final fake = FakeSchoolClassRepository();
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create classes'));
    await tester.pumpAndSettle();

    expect(find.text('Tick at least one class.'), findsOneWidget);
    expect(fake.quickSetupClasses, isNull);
  });

  testWidgets('a school without an academic year is told to add one first', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository(), years: const []));
    await _open(tester);

    expect(find.text('Add an academic year first - classes belong to a year.'), findsOneWidget);
  });

  testWidgets('a server error keeps the dialog open and says why', (tester) async {
    final fake = FakeSchoolClassRepository(
      failQuickSetupWith: const Failure(code: 'VALIDATION_ERROR', message: 'Not a standard class: Rose.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _open(tester);

    await tester.tap(find.text('Create 4 classes'));
    await tester.pumpAndSettle();

    expect(find.text('Not a standard class: Rose.'), findsOneWidget);
    expect(find.byType(QuickClassSetupDialog), findsOneWidget);
  });
}
