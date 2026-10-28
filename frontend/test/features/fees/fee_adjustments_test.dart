import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/fees/data/fee_repository.dart';
import 'package:edutrack_app/features/fees/data/models/student_fees.dart';
import 'package:edutrack_app/features/fees/presentation/fee_discounts_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_fee_repository.dart';
import '../../support/fake_school_repository.dart';
import 'student_fees_screen_test.dart' show useDesktop, wrap;

/// Discounts, waivers and late fines on a student's fees (docs/fees.md, F4).

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<FakeFeeRepository> openStatement(WidgetTester tester, {UserRole role = UserRole.accountant}) async {
  useDesktop(tester);
  final fees = FakeFeeRepository()..statements = {7: fakeAdjustedStatement()};
  await tester.pumpWidget(wrap(fees, at: '/student-fees?student=7', role: role));
  await tester.pumpAndSettle();
  return fees;
}

Widget wrapDiscounts(FakeFeeRepository fees, {UserRole role = UserRole.accountant}) {
  final router = GoRouter(
    initialLocation: '/fee-discounts',
    routes: [
      GoRoute(
        path: '/fee-discounts',
        builder: (context, state) => const Scaffold(body: FeeDiscountsScreen()),
      ),
      GoRoute(
        path: '/student-fees',
        builder: (context, state) => const Scaffold(body: Text('Student page')),
      ),
    ],
  );

  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      feeRepositoryProvider.overrideWithValue(fees),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: AuthenticatedUser(id: 9, name: 'Meena', email: 'm@example.com', role: role),
        ),
      ),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  );
}

void main() {
  group('the statement', () {
    testWidgets('shows each discount, the fine and the waiver plainly', (tester) async {
      await openStatement(tester);

      // The discount, on the line and in its own section.
      expect(find.textContaining('Discount INR'), findsWidgets);
      expect(find.text('Discounts'), findsOneWidget);
      expect(find.textContaining('off each Tuition installment'), findsOneWidget);
      // The fine is labelled as one.
      expect(find.text('Late fine'), findsOneWidget);
      expect(find.text('Added 05/18/2026'), findsOneWidget);
      // The waiver says why, and what was forgiven is totalled.
      expect(find.textContaining('waived: Hardship'), findsOneWidget);
      expect(find.text('Waived'), findsWidgets);
    });

    testWidgets('only what is still owed can be waived', (tester) async {
      await openStatement(tester);

      // The discounted installment and the fine - not the waived one.
      expect(find.byTooltip('Waive'), findsNWidgets(2));
    });

    testWidgets('a role that only reads is offered nothing to change', (tester) async {
      await openStatement(tester, role: UserRole.superAdmin);

      expect(find.text('Add Discount'), findsNothing);
      expect(find.byTooltip('Waive'), findsNothing);
      expect(find.text('End discount'), findsNothing);
    });
  });

  testWidgets('a line a discount covers in full reads as covered, and is not offered for waiving', (tester) async {
    useDesktop(tester);
    final base = fakeAdjustedStatement();
    final covered = FeeDue(
      id: 8,
      feeHeadName: 'Tuition',
      feeHeadId: 2,
      label: 'Tuition - July 2026',
      dueDate: DateTime(2026, 7, 10),
      amount: '2000.00',
      discountAmount: '2000.00',
      paidAmount: '0.00',
      balance: '0.00',
      status: FeeDueStatus.pending,
      isOverdue: false,
    );
    final fees = FakeFeeRepository()
      ..statements = {
        7: StudentFeeStatement(
          student: base.student,
          academicYearId: base.academicYearId,
          academicYearName: base.academicYearName,
          currencyCode: base.currencyCode,
          dues: [covered],
          totals: base.totals,
          concessions: base.concessions,
        ),
      };
    await tester.pumpWidget(wrap(fees, at: '/student-fees?student=7'));
    await tester.pumpAndSettle();

    expect(find.text('Covered by discount'), findsOneWidget);
    expect(find.byTooltip('Waive'), findsNothing);
    // Nothing on it to pay, so no Record Payment either.
    expect(find.text('Record Payment'), findsNothing);
  });

  group('adding a discount', () {
    testWidgets('needs a value and a reason, and says a fixed amount is per installment', (tester) async {
      final fees = await openStatement(tester);
      await tester.tap(find.text('Add Discount'));
      await tester.pumpAndSettle();

      expect(find.text('Off each installment, not once for the year.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add discount'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a value above zero.'), findsOneWidget);
      expect(find.text('Say why the discount is given.'), findsOneWidget);
      expect(fees.discounts, isEmpty);
    });

    testWidgets('a percentage over 100 is refused', (tester) async {
      final fees = await openStatement(tester);
      await tester.tap(find.text('Add Discount'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Percentage').first);
      await tester.pumpAndSettle();
      await tester.enterText(field('Percentage'), '120');
      await tester.enterText(field('Reason'), 'Scholarship');
      await tester.tap(find.widgetWithText(FilledButton, 'Add discount'));
      await tester.pumpAndSettle();

      expect(find.text('A percentage cannot be more than 100.'), findsOneWidget);
      expect(fees.discounts, isEmpty);
    });

    testWidgets('a fixed amount on one fee type is sent as it was typed', (tester) async {
      final fees = await openStatement(tester);
      await tester.tap(find.text('Add Discount'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int?>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tuition').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount (INR)'), '500');
      await tester.enterText(field('Reason'), 'Sibling discount');
      await tester.tap(find.widgetWithText(FilledButton, 'Add discount'));
      await tester.pumpAndSettle();

      expect(fees.discounts.single, {
        'student_id': 7,
        'academic_year_id': 1,
        'fee_head_id': 2,
        'kind': 'fixed',
        'value': '500.00',
        'reason': 'Sibling discount',
      });
      expect(find.text('Discount added - 5 installments lowered.'), findsOneWidget);
    });

    testWidgets('what the server refuses is shown in the dialog', (tester) async {
      final fees = await openStatement(tester);
      fees.failDiscountWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The given data was invalid.',
        details: {
          'errors': {
            'value': ['The value must be more than zero.'],
          },
        },
      );
      await tester.tap(find.text('Add Discount'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount (INR)'), '500');
      await tester.enterText(field('Reason'), 'Sibling discount');
      await tester.tap(find.widgetWithText(FilledButton, 'Add discount'));
      await tester.pumpAndSettle();

      expect(find.text('The value must be more than zero.'), findsOneWidget);
      expect(find.text('Add discount - Asha Rao'), findsOneWidget);
    });
  });

  group('waiving', () {
    testWidgets('asks why, then forgives the installment', (tester) async {
      final fees = await openStatement(tester);

      await tester.tap(find.byTooltip('Waive').first);
      await tester.pumpAndSettle();
      expect(find.text('Waive "Tuition - May 2026"?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Waive'));
      await tester.pumpAndSettle();
      expect(find.text('Give a reason.'), findsOneWidget);
      expect(fees.waived, isEmpty);

      await tester.enterText(field('Reason'), 'Hardship');
      await tester.tap(find.widgetWithText(FilledButton, 'Waive'));
      await tester.pumpAndSettle();

      expect(fees.waived.single, (id: 2, reason: 'Hardship'));
      expect(find.text('"Tuition - May 2026" waived.'), findsOneWidget);
    });
  });

  group('the Discounts list', () {
    testWidgets('lists discounts, and ending one asks first', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..concessionRows = [fakeConcession()];
      await tester.pumpWidget(wrapDiscounts(fees));
      await tester.pumpAndSettle();

      expect(find.textContaining('off each Tuition installment'), findsOneWidget);
      expect(find.textContaining('Sibling discount'), findsOneWidget);

      await tester.tap(find.text('End discount'));
      await tester.pumpAndSettle();
      expect(find.text('End this discount?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'End discount'));
      await tester.pumpAndSettle();

      expect(fees.revoked, [90]);
      expect(find.text('Discount ended.'), findsOneWidget);
    });

    testWidgets('ended ones show only when asked for', (tester) async {
      useDesktop(tester);
      final fees = FakeFeeRepository()..concessionRows = [fakeConcession(revoked: true)];
      await tester.pumpWidget(wrapDiscounts(fees));
      await tester.pumpAndSettle();

      expect(find.text('No discount has been given yet.'), findsOneWidget);

      await tester.tap(find.text('Show ended ones'));
      await tester.pumpAndSettle();

      expect(fees.concessionQueries.last['include_revoked'], isTrue);
      expect(find.text('Ended'), findsOneWidget);
      expect(find.text('End discount'), findsNothing);
    });
  });
}
