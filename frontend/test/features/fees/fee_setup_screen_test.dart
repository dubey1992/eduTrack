import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/fees/data/fee_repository.dart';
import 'package:edutrack_app/features/fees/data/models/fee_structure.dart';
import 'package:edutrack_app/features/fees/data/money_text.dart';
import 'package:edutrack_app/features/fees/presentation/fee_setup_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_term_repository.dart';
import '../../support/fake_academic_year_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_fee_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/fake_transport_repository.dart';
import '../../support/transport_fixtures.dart';

const class8 = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Test School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Class 8',
  level: 8,
  sections: [],
);

AuthenticatedUser actor(UserRole role, {ModuleAccess access = const ModuleAccess.unspecified()}) =>
    AuthenticatedUser(id: 9, name: 'Meena Iyer', email: 'meena@example.com', role: role, access: access);

Widget wrap(
  FakeFeeRepository fees, {
  UserRole role = UserRole.accountant,
  ModuleAccess access = const ModuleAccess.unspecified(),
  List<SchoolClass> classes = const [class8],
  FakeTransportRepository? transport,
  List<AcademicYear>? years,
}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      feeRepositoryProvider.overrideWithValue(fees),
      academicYearRepositoryProvider.overrideWithValue(FakeAcademicYearRepository(years: years ?? [fakeYear()])),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: List.of(classes))),
      transportRepositoryProvider.overrideWithValue(transport ?? FakeTransportRepository(routes: [greenPark])),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor(role, access: access))),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: FeeSetupScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

/// Inside the open dialog only - the screen behind it has dropdowns of its own.
Finder inDialog(Finder finder) => find.descendant(of: find.byType(AlertDialog), matching: finder);

const validationError = Failure(
  code: 'VALIDATION_ERROR',
  message: 'The given data was invalid.',
  details: {
    'errors': {
      'fee_head_id': ['Class 8 already has a Tuition fee for 2026-27.'],
    },
  },
);

void main() {
  group('money as text', () {
    test('reads amounts to the cent, and nothing that is not one', () {
      expect(centsOf('12000'), 1200000);
      expect(centsOf('1200.5'), 120050);
      expect(centsOf(' 0.05 '), 5);
      expect(centsOf('1.234'), isNull);
      expect(centsOf('-5'), isNull);
      expect(centsOf('abc'), isNull);
      expect(centsOf(''), isNull);
    });

    test('writes them the way the server does', () {
      expect(textOfCents(120050), '1200.50');
      expect(textOfCents(5), '0.05');
      expect(textOfCents(1200000), '12000.00');
    });
  });

  group('who sees what', () {
    testWidgets('an accountant may add fee types; Transport is there and cannot be touched', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Bus routes'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add Fee Type'), findsOneWidget);
      // Rename/Retire/Delete for Tuition, none for Transport.
      expect(find.text('Rename'), findsOneWidget);
      expect(find.byTooltip('Delete fee type'), findsOneWidget);
    });

    testWidgets('a role the matrix gives only "view" reads and is offered nothing to change', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository(structures: [fakeClassFee()]);
      await tester.pumpWidget(
        wrap(
          fees,
          role: UserRole.teacher,
          access: const ModuleAccess(permissions: {AppModules.fees: PermissionLevel.view}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('View only - fees are set up by the school.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add Fee Type'), findsNothing);
      expect(find.text('Rename'), findsNothing);

      await openTab(tester, 'Class Fees');
      expect(find.text('Add fee'), findsNothing);
      expect(find.text('Publish'), findsNothing);
      expect(find.text('View'), findsOneWidget);
    });

    testWidgets('a super admin is asked to choose a school first', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository(), role: UserRole.superAdmin));
      await tester.pumpAndSettle();

      expect(find.text('Choose a school to see its fees.'), findsOneWidget);
    });

    testWidgets('a school without the module is told so, with no retry', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()
        ..failWith = const Failure(
          code: Failure.moduleDisabledCode,
          message: 'Fee Management is switched off for this school.',
        );
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();

      expect(find.text('Fee Management is switched off for this school.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a list that cannot be read offers a retry', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..failWith = Failure.network();
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach the server'), findsOneWidget);

      fees.failWith = null;
      await tapText(tester, 'Retry');
      expect(find.text('Tuition'), findsOneWidget);
    });
  });

  testWidgets('fee types can be set up before any academic year exists; fees wait for one', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeFeeRepository(), years: const []));
    await tester.pumpAndSettle();

    expect(find.text('Tuition'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add Fee Type'), findsOneWidget);

    await openTab(tester, 'Class Fees');
    expect(find.textContaining('Fees are set per academic year, and there is none yet'), findsOneWidget);
  });

  group('fee types', () {
    testWidgets('a name is required, a duplicate is refused at the box, and a new one is added', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository();
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();

      await tapText(tester, 'Add Fee Type');
      await tapText(tester, 'Add');
      expect(find.text('Enter a name for the fee type.'), findsOneWidget);

      await tester.enterText(field('Name'), 'tuition');
      await tapText(tester, 'Add');
      expect(find.text('A fee type with this name already exists.'), findsOneWidget);

      await tester.enterText(field('Name'), 'Exam');
      await tapText(tester, 'Add');

      expect(find.text('Fee type "Exam" added.'), findsOneWidget);
      expect(find.text('Exam'), findsOneWidget);
    });

    testWidgets('retiring asks first, in the app, and can be undone', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository()));
      await tester.pumpAndSettle();

      await tapText(tester, 'Retire');
      expect(find.text('Retire "Tuition"?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Retire'));
      await tester.pumpAndSettle();

      expect(find.text('Retired'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
    });

    testWidgets('a type in use cannot be deleted - only retired', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository(structures: [fakeClassFee()])));
      await tester.pumpAndSettle();

      expect(find.text('Used by 1 fee.'), findsOneWidget);
      expect(find.byTooltip('Delete fee type'), findsNothing);
    });
  });

  group('class fees', () {
    Future<void> openAddFee(WidgetTester tester) async {
      await openTab(tester, 'Class Fees');
      await tapText(tester, 'Add fee');
    }

    testWidgets('each class of the year is listed, with what it pays', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository(structures: [fakeClassFee()])));
      await tester.pumpAndSettle();
      await openTab(tester, 'Class Fees');

      expect(find.text('Class 8'), findsOneWidget);
      expect(find.textContaining('Total for the year'), findsOneWidget);
      expect(find.textContaining('Per term · 2 installments'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
    });

    testWidgets('a year with no classes says where to add them', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository(), classes: const []));
      await tester.pumpAndSettle();
      await openTab(tester, 'Class Fees');

      expect(find.textContaining('There are no classes in 2026-27 yet'), findsOneWidget);
    });

    testWidgets('installments come from the frequency, must add up, and save as a draft', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository();
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();
      await openAddFee(tester);

      // Filling in before there is an amount asks for one.
      await tapText(tester, 'Fill in monthly');
      expect(find.text('Enter the fee amount first.'), findsOneWidget);
      expect(fees.planCalls, 0);

      // Nothing chosen: refused before the server is asked.
      await tapText(tester, 'Save as draft');
      expect(find.text('Choose a fee type.'), findsOneWidget);
      expect(fees.created, isEmpty);

      await tester.tap(inDialog(find.byType(DropdownButtonFormField<int>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tuition').last);
      await tester.pumpAndSettle();

      await tester.enterText(field('Amount for the year'), '12000');
      await tapText(tester, 'Fill in monthly');
      expect(fees.planCalls, 1);
      expect(find.text('Installments total 12000.00 of 12000.00'), findsOneWidget);

      // Change the fee without changing the installments: they no longer add up.
      await tester.enterText(field('Amount for the year'), '13000');
      await tester.pump();
      await tapText(tester, 'Save as draft');
      expect(find.text('The installments add up to 12000.00, but the fee is 13000.00.'), findsOneWidget);
      expect(fees.created, isEmpty);

      await tester.enterText(field('Amount for the year'), '12000');
      await tapText(tester, 'Save as draft');

      expect(fees.created.single['fee_head_id'], 2);
      expect(fees.created.single['school_class_id'], 1);
      expect(fees.created.single['transport_route_id'], isNull);
      expect(fees.created.single['installments_total'], '12000.00');
      expect(find.text('Tuition for Class 8 saved as a draft.'), findsOneWidget);
    });

    testWidgets('an installment can be removed, and the total follows', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository()));
      await tester.pumpAndSettle();
      await openAddFee(tester);

      await tester.enterText(field('Amount for the year'), '12000');
      await tapText(tester, 'Fill in monthly');
      await tester.tap(find.byTooltip('Remove installment').first);
      await tester.pumpAndSettle();

      expect(find.text('Installments total 6000.00 of 12000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('what the server refuses is shown in the dialog', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..failSaveWith = validationError;
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();
      await openAddFee(tester);

      await tester.tap(inDialog(find.byType(DropdownButtonFormField<int>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tuition').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount for the year'), '12000');
      await tapText(tester, 'Fill in monthly');
      await tapText(tester, 'Save as draft');

      expect(find.text('Class 8 already has a Tuition fee for 2026-27.'), findsOneWidget);
      expect(find.text('The given data was invalid.'), findsOneWidget);
    });

    testWidgets('a fee type the class already has is not offered again', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeFeeRepository(structures: [fakeClassFee()])));
      await tester.pumpAndSettle();
      await openAddFee(tester);

      expect(find.textContaining('Every fee type already has a fee here'), findsOneWidget);
    });

    testWidgets('publishing asks first and marks the fee published', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository(structures: [fakeClassFee()]);
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();
      await openTab(tester, 'Class Fees');

      await tester.tap(find.widgetWithText(TextButton, 'Publish'));
      await tester.pumpAndSettle();
      expect(find.text('Publish Tuition for Class 8?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(fees.published, [50]);
      expect(find.text('Published'), findsOneWidget);
      expect(find.text('Tuition for Class 8 published. 32 students charged.'), findsOneWidget);
      expect(find.byTooltip('Delete draft'), findsNothing);
    });

    testWidgets('a draft can be deleted after a confirmation', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository(structures: [fakeClassFee()]);
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();
      await openTab(tester, 'Class Fees');

      await tester.tap(find.byTooltip('Delete draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fees.deleted, [50]);
      expect(find.text('No fees set for 2026-27.'), findsOneWidget);
    });

    testWidgets('every draft of the year can be published at once', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository(structures: [fakeClassFee()]);
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();
      await openTab(tester, 'Class Fees');

      await tapText(tester, 'Publish 1 draft for 2026-27');
      await tester.tap(find.widgetWithText(FilledButton, 'Publish all'));
      await tester.pumpAndSettle();

      expect(fees.publishAllCalls, 1);
      expect(find.text('1 fee published. 32 students charged.'), findsOneWidget);
    });
  });

  group('bus route fees', () {
    testWidgets('a route is charged under Transport, and only once', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository();
      await tester.pumpWidget(wrap(fees));
      await tester.pumpAndSettle();
      await openTab(tester, 'Bus Route Fees');

      expect(find.text('Green Park'), findsOneWidget);
      await tapText(tester, 'Add fee');

      // The fee type is not a choice here.
      expect(inDialog(find.byType(DropdownButtonFormField<int>)), findsNothing);
      await tester.enterText(field('Amount for the year'), '12000');
      await tapText(tester, 'Fill in monthly');
      await tapText(tester, 'Save as draft');

      expect(fees.created.single['transport_route_id'], 1);
      expect(fees.created.single['fee_head_id'], 1);
      expect(find.text('Add fee'), findsNothing);
    });

    testWidgets('a school with transport switched off is told so', (tester) async {
      useDesktop(tester);
      final transport = FakeTransportRepository(
        failWith: const Failure(
          code: Failure.moduleDisabledCode,
          message: 'Transport is switched off for this school.',
        ),
      );
      await tester.pumpWidget(wrap(FakeFeeRepository(), transport: transport));
      await tester.pumpAndSettle();
      await openTab(tester, 'Bus Route Fees');

      expect(find.text('Transport is switched off for this school.'), findsOneWidget);
    });
  });

  test('a frequency reads back from the server unchanged', () {
    for (final frequency in FeeFrequency.values) {
      expect(FeeFrequency.fromWire(frequency.wire), frequency);
    }
  });
}
