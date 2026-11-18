import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/reports/application/report_link.dart';
import 'package:edutrack_app/features/reports/data/models/report.dart';
import 'package:edutrack_app/features/reports/data/report_repository.dart';
import 'package:edutrack_app/features/reports/presentation/reports_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_report_repository.dart';
import '../../support/fake_school_repository.dart';

/// The fee collection report opened from the dashboard (docs/dashboard.md):
/// the link it arrives with, Today, and the person and payment-mode filters.

const _accountant = AuthenticatedUser(id: 7, name: 'Meena', email: 'm@example.com', role: UserRole.accountant);

final _collection = ReportResult.fromJson({
  'range': {'from': '2026-10-28', 'to': '2026-10-28', 'working_days': null},
  'rows': [
    {
      'receipt_date': '2026-10-28',
      'receipt_number': 'RCPT-2026-27-00001',
      'student': 'Kabir Shah',
      'payment_mode': 'Cash',
      'received_by': 'Rahul Sharma',
      'amount': '3000.00',
      'credit_amount': '250.00',
      'currency_code': 'INR',
    },
  ],
  'totals': {
    'receipts': 1,
    'collected': [
      {'currency_code': 'INR', 'amount': '3000.00'},
    ],
    'cancelled_receipts': 0,
    'cancelled_amount': <Object>[],
    'by_mode': [
      {'payment_mode': 'cash', 'label': 'Cash', 'currency_code': 'INR', 'receipts': 1, 'amount': '3000.00'},
    ],
    'by_staff': [
      {
        'received_by_id': 7,
        'received_by': 'Rahul Sharma',
        'currency_code': 'INR',
        'receipts': 1,
        'amount': '3000.00',
        'cash': '3000.00',
        'credit_amount': '250.00',
      },
    ],
  },
});

Widget _wrap(FakeReportRepository fake, ReportLink link) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      reportRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _accountant)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ReportsScreen(link: link)),
    ),
  );
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('the link', () {
    test('reads a report, a whole range and the filters', () {
      final link = ReportLink.fromQuery({
        'report': 'fee-collection',
        'from': '2026-10-01',
        'to': '2026-10-28',
        'received_by': '7',
        'received_by_name': 'Rahul Sharma',
        'payment_mode': 'upi',
      });

      expect(link.kind, ReportKind.feeCollection);
      expect((link.from, link.to), (DateTime(2026, 10), DateTime(2026, 10, 28)));
      expect((link.receivedBy, link.receivedByName, link.paymentMode), (7, 'Rahul Sharma', 'upi'));
    });

    test('ignores what it cannot use rather than failing', () {
      final link = ReportLink.fromQuery({'report': 'nonsense', 'from': '2026-10-28', 'received_by': 'rahul'});

      expect(link.kind, isNull);
      // Half a range is no range.
      expect((link.from, link.to), (null, null));
      expect(link.receivedBy, isNull);
      expect(link.isEmpty, isTrue);
    });

    test('carries the school picked on the dashboard', () {
      final link = ReportLink.fromQuery({'report': 'fee-outstanding', 'school_id': '420'});

      expect((link.kind, link.schoolId), (ReportKind.feeOutstanding, 420));
      expect(link.location, '/reports?report=fee-outstanding&school_id=420');
    });

    test('a range that ends before it starts is dropped', () {
      final link = ReportLink.fromQuery({'from': '2026-10-28', 'to': '2026-10-01'});

      expect((link.from, link.to), (null, null));
    });

    test('goes there and back unchanged', () {
      final link = ReportLink(
        kind: ReportKind.feeCollection,
        from: DateTime(2026, 10, 28),
        to: DateTime(2026, 10, 28),
        receivedBy: 7,
        receivedByName: 'Rahul Sharma',
      );

      expect(ReportLink.fromQuery(Uri.parse(link.location).queryParameters), link);
    });
  });

  group('the screen', () {
    testWidgets('opens on the linked report, day and person, and asks the server for exactly that', (tester) async {
      _desktop(tester);
      final fake = FakeReportRepository(resultsByKind: {ReportKind.feeCollection: _collection});
      final link = ReportLink(
        kind: ReportKind.feeCollection,
        from: DateTime(2026, 10, 28),
        to: DateTime(2026, 10, 28),
        receivedBy: 7,
        receivedByName: 'Rahul Sharma',
      );

      await tester.pumpWidget(_wrap(fake, link));
      await tester.pumpAndSettle();

      expect(fake.lastKind, ReportKind.feeCollection);
      expect((fake.lastFrom, fake.lastTo), ('2026-10-28', '2026-10-28'));
      expect(fake.lastReceivedBy, 7);
      expect(find.text('Received by Rahul Sharma'), findsOneWidget);
      // Per person in the summary, and the credit column in the table.
      expect(find.text('Rahul Sharma (1)'), findsOneWidget);
      expect(find.text('Held as credit'), findsOneWidget);
      expect(find.textContaining('{'), findsNothing);
    });

    testWidgets('a payment mode narrows it, and Everyone undoes the person', (tester) async {
      _desktop(tester);
      final fake = FakeReportRepository(resultsByKind: {ReportKind.feeCollection: _collection});
      await tester.pumpWidget(
        _wrap(fake, const ReportLink(kind: ReportKind.feeCollection, receivedBy: 7, receivedByName: 'Rahul Sharma')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('report-payment-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      expect(fake.lastPaymentMode, 'upi');

      await tester.tap(find.byKey(const Key('report-received-by')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Everyone').last);
      await tester.pumpAndSettle();
      expect(fake.lastReceivedBy, isNull);
      expect(fake.lastPaymentMode, 'upi', reason: 'the other filter stays');
    });

    testWidgets('Today sets the period to the one day', (tester) async {
      _desktop(tester);
      final fake = FakeReportRepository(resultsByKind: {ReportKind.feeCollection: _collection});
      await tester.pumpWidget(_wrap(fake, const ReportLink(kind: ReportKind.feeCollection)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('report-today')));
      await tester.pumpAndSettle();

      expect(fake.lastFrom, isNotNull);
      expect(fake.lastFrom, fake.lastTo);
    });

    testWidgets('the filters belong to fee collection only', (tester) async {
      _desktop(tester);
      final fake = FakeReportRepository(resultsByKind: {ReportKind.feeCollection: _collection});
      await tester.pumpWidget(
        _wrap(fake, const ReportLink(kind: ReportKind.feeCollection, receivedBy: 7, paymentMode: 'cash')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Payroll summary'));
      await tester.pumpAndSettle();

      expect(fake.lastKind, ReportKind.payrollSummary);
      expect((fake.lastReceivedBy, fake.lastPaymentMode), (null, null));
      expect(find.byKey(const Key('report-received-by')), findsNothing);
    });

    testWidgets('a payment mode the app does not know is not applied', (tester) async {
      _desktop(tester);
      final fake = FakeReportRepository(resultsByKind: {ReportKind.feeCollection: _collection});
      await tester.pumpWidget(_wrap(fake, const ReportLink(kind: ReportKind.feeCollection, paymentMode: 'barter')));
      await tester.pumpAndSettle();

      expect(fake.lastPaymentMode, isNull);
    });

    testWidgets('opens on the school the link names', (tester) async {
      _desktop(tester);
      final fake = FakeReportRepository(resultsByKind: {ReportKind.feeCollection: _collection});
      await tester.pumpWidget(_wrap(fake, const ReportLink(kind: ReportKind.feeCollection, schoolId: 420)));
      await tester.pumpAndSettle();

      expect(fake.lastSchoolId, 420);
    });

    testWidgets('a quiet period shows no empty per-mode or per-person figure', (tester) async {
      _desktop(tester);
      final quiet = ReportResult.fromJson({
        'range': {'from': '2026-11-01', 'to': '2026-11-17', 'working_days': null},
        'rows': <Object>[],
        'totals': {
          'receipts': 0,
          'collected': <Object>[],
          'cancelled_receipts': 0,
          'cancelled_amount': <Object>[],
          'by_mode': <Object>[],
          'by_staff': <Object>[],
        },
      });
      await tester.pumpWidget(
        _wrap(
          FakeReportRepository(resultsByKind: {ReportKind.feeCollection: quiet}),
          const ReportLink(kind: ReportKind.feeCollection),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('By Mode'), findsNothing);
      expect(find.text('By Staff'), findsNothing);
      expect(find.text('Nothing to report for this period.'), findsOneWidget);
    });
  });
}
