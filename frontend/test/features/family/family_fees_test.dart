import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/utils/currency_formatter.dart';
import 'package:edutrack_app/features/family/data/models/family_fees.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart';

/// The Fees tab (docs/parent-student-app.md, F3): what is owed, how to pay,
/// each instalment, the receipts and the statement - and every state.
/// Scrolls the Fees list until [finder] is built and on screen: rows below
/// the fold do not exist until they are scrolled to.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(of: find.byKey(const Key('family-fees')), matching: find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a child with fees', () {
    testWidgets('shows what is left, what is overdue, and each instalment where it stands', (tester) async {
      await pumpFamilyApp(tester, goTo: '/fees');

      expect(find.text('Fees for 2026-27'), findsOneWidget);
      expect(find.byKey(const Key('family-fees-balance')), findsOneWidget);
      expect(find.textContaining('of it is overdue'), findsOneWidget);
      expect(find.text('Discount'), findsOneWidget);

      for (final (id, status) in [(1, 'Paid'), (2, 'Overdue'), (3, 'Due')]) {
        final card = find.byKey(Key('family-instalment-$id'));
        await reveal(tester, card);
        expect(
          find.descendant(of: card, matching: find.text(status)),
          findsOneWidget,
          reason: 'instalment $id',
        );
      }
      expect(find.textContaining('paid of'), findsOneWidget, reason: 'the part-paid overdue line says how much');
    });

    testWidgets('says how to pay at this school, in its own words', (tester) async {
      await pumpFamilyApp(tester, goTo: '/fees');

      expect(find.byKey(const Key('family-how-to-pay')), findsOneWidget);
      expect(find.text('Mon-Sat, 9 am to 1 pm'), findsOneWidget);
      expect(find.text('greenfield@okaxis'), findsOneWidget);
      expect(find.textContaining('does not take payments'), findsOneWidget);
    });

    testWidgets('copies the UPI ID and says so', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpFamilyApp(tester, goTo: '/fees');

      await tester.tap(find.byKey(const Key('family-copy-upi')));
      await tester.pumpAndSettle();

      expect(copied, ['greenfield@okaxis']);
      expect(find.text('UPI ID copied'), findsOneWidget);
    });

    testWidgets('pays what is overdue with any UPI app, the school named and the child noted (6.4)', (tester) async {
      final (_, _, opened) = await pumpFamilyApp(tester, goTo: '/fees');

      await reveal(tester, find.byKey(const Key('family-pay-upi')));
      expect(find.text('Pay ${formatCurrency(3500, 'INR')} with any UPI app'), findsOneWidget);
      await tester.tap(find.byKey(const Key('family-pay-upi')));
      await tester.pumpAndSettle();

      expect(
        opened.single.toString(),
        'upi://pay?pa=greenfield@okaxis&pn=Greenfield%20School&am=3500.00&cu=INR'
        '&tn=Fees%20-%20Aarav%20Sharma%20(ADM-102)',
      );
      expect(find.textContaining('the school records it'), findsOneWidget);
    });

    testWidgets('a phone with no UPI app is told to copy the UPI ID instead', (tester) async {
      await pumpFamilyApp(tester, goTo: '/fees', opens: false);

      await reveal(tester, find.byKey(const Key('family-pay-upi')));
      await tester.tap(find.byKey(const Key('family-pay-upi')));
      await tester.pumpAndSettle();

      expect(find.textContaining('No UPI app opened'), findsOneWidget);
    });

    testWidgets('no UPI button where UPI cannot be used: another currency, or no UPI ID', (tester) async {
      final abroad = FakeFamilyRepository()..feesValue = familyFees(currencyCode: 'USD');
      await pumpFamilyApp(tester, data: abroad, goTo: '/fees');
      expect(find.byKey(const Key('family-pay-upi')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      final noUpi = FakeFamilyRepository()
        ..feesValue = familyFees(howToPay: const HowToPay(counterHours: 'Mon-Sat, 9 am to 1 pm'));
      await pumpFamilyApp(tester, data: noUpi, goTo: '/fees');
      expect(find.byKey(const Key('family-pay-upi')), findsNothing);
    });

    testWidgets('calls the office about fees', (tester) async {
      final (_, _, opened) = await pumpFamilyApp(tester, goTo: '/fees');

      await reveal(tester, find.byKey(const Key('family-call-office')));
      await tester.tap(find.byKey(const Key('family-call-office')));
      await tester.pumpAndSettle();

      expect(opened.single.toString(), 'tel:+918040001234');
    });

    testWidgets('a receipt opens as its PDF; a cancelled one is marked', (tester) async {
      final handed = <String>[];
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/fees', onPdf: (bytes, name) async => handed.add(name));

      final cancelled = find.byKey(const Key('family-receipt-12'));
      await reveal(tester, cancelled);
      expect(find.descendant(of: cancelled, matching: find.text('Cancelled by the office')), findsOneWidget);

      await reveal(tester, find.byKey(const Key('family-receipt-11')));
      await tester.tap(find.byKey(const Key('family-receipt-11')));
      await tester.pumpAndSettle();

      expect(data.pdfsAskedFor, ['receipt:${aarav.id}:11']);
      expect(handed, ['receipt-RC-2026-0042.pdf']);
    });

    testWidgets('the year\'s statement downloads as a PDF', (tester) async {
      final handed = <String>[];
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/fees', onPdf: (bytes, name) async => handed.add(name));

      await reveal(tester, find.byKey(const Key('family-fee-statement')));
      await tester.tap(find.byKey(const Key('family-fee-statement')));
      await tester.pumpAndSettle();

      expect(data.pdfsAskedFor, ['statement:${aarav.id}']);
      expect(handed.single, startsWith('fee-statement-aarav-2026-27'));
    });

    testWidgets('a PDF that cannot be fetched says why', (tester) async {
      final data = FakeFamilyRepository()..failPdfWith = Failure.network();
      final handed = <String>[];
      await pumpFamilyApp(tester, data: data, goTo: '/fees', onPdf: (bytes, name) async => handed.add(name));

      await reveal(tester, find.byKey(const Key('family-fee-statement')));
      await tester.tap(find.byKey(const Key('family-fee-statement')));
      await tester.pumpAndSettle();

      expect(handed, isEmpty);
      expect(find.text(Failure.network().message), findsOneWidget);
    });
  });

  group('the other states', () {
    testWidgets('no fees set yet says so, with no statement to download', (tester) async {
      final data = FakeFamilyRepository()..feesValue = familyFees(empty: true);
      await pumpFamilyApp(tester, data: data, goTo: '/fees');

      expect(find.text('No fees set yet'), findsOneWidget);
      expect(find.textContaining('No payments this year yet'), findsOneWidget);
      expect(find.byKey(const Key('family-fee-statement')), findsNothing);
    });

    testWidgets('a school that wrote nothing on paying shows no payment card', (tester) async {
      final data = FakeFamilyRepository()..feesValue = familyFees(howToPay: const HowToPay());
      await pumpFamilyApp(tester, data: data, goTo: '/fees');

      expect(find.byKey(const Key('family-how-to-pay')), findsNothing);
    });

    testWidgets('credit the school holds is shown', (tester) async {
      final data = FakeFamilyRepository()..feesValue = familyFees(credit: 750);
      await pumpFamilyApp(tester, data: data, goTo: '/fees');

      expect(find.text('Credit held'), findsOneWidget);
    });

    testWidgets('a failure says what went wrong and tries again', (tester) async {
      final data = FakeFamilyRepository()..failFeesWith = Failure.network();
      await pumpFamilyApp(tester, data: data, goTo: '/fees');

      expect(find.text('No connection'), findsOneWidget);

      data.failFeesWith = null;
      await tester.tap(find.byKey(const Key('family-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('family-fees-summary')), findsOneWidget);
    });
  });
}
