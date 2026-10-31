import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';
import 'package:edutrack_app/features/payments/presentation/add_payment_dialog.dart';
import 'package:edutrack_app/features/payments/presentation/edit_payment_dialog.dart';
import 'package:edutrack_app/features/payments/presentation/payment_receipt_dialog.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payment_repository.dart';
import '../../support/fake_school_repository.dart';

/// One payment, several services: tick a service and type its amount, add
/// "other" fees by name, and the total adds itself up.

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

Widget wrap(FakePaymentRepository fake, Widget dialog) {
  return ProviderScope(
    overrides: [
      paymentRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: const [_school])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => dialog),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _chooseSchool(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'School'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sunrise Public School (INR)').last);
  await tester.pumpAndSettle();
}

Future<void> _tick(WidgetTester tester, String service) async {
  await tester.tap(find.text(service));
  await tester.pumpAndSettle();
}

String _total(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('services-total'))).data!;

void main() {
  group('the Add Payment form', () {
    testWidgets('a service amount box opens only when the service is ticked', (tester) async {
      _tall(tester);
      await tester.pumpWidget(wrap(FakePaymentRepository(), const AddPaymentDialog()));
      await _open(tester);

      expect(find.byKey(const Key('amount-setup_fee')), findsNothing);

      await _tick(tester, 'Setup Fee');
      expect(find.byKey(const Key('amount-setup_fee')), findsOneWidget);

      await _tick(tester, 'Setup Fee');
      expect(find.byKey(const Key('amount-setup_fee')), findsNothing);
    });

    testWidgets('the total adds up every ticked service and other fee, in the school currency', (tester) async {
      _tall(tester);
      await tester.pumpWidget(wrap(FakePaymentRepository(), const AddPaymentDialog()));
      await _open(tester);
      await _chooseSchool(tester);

      await _tick(tester, 'Setup Fee');
      await tester.enterText(find.byKey(const Key('amount-setup_fee')), '25000');
      await _tick(tester, 'Annual Maintenance');
      await tester.enterText(find.byKey(const Key('amount-annual_maintenance')), '12000.50');
      await tester.tap(find.byKey(const Key('add-other-fee')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('other-name-0')), 'Staff training day');
      await tester.enterText(find.byKey(const Key('other-amount-0')), '5000');
      await tester.pumpAndSettle();

      expect(_total(tester), contains('42,000.50'));
      expect(_total(tester), contains('INR'));

      // Unticking a service takes its amount out of the total.
      await _tick(tester, 'Annual Maintenance');
      expect(_total(tester), contains('30,000.00'));
    });

    testWidgets('saves every service, in order, with the other fee by name', (tester) async {
      _tall(tester);
      final fake = FakePaymentRepository();
      await tester.pumpWidget(wrap(fake, const AddPaymentDialog()));
      await _open(tester);
      await _chooseSchool(tester);

      await _tick(tester, 'Setup Fee');
      await tester.enterText(find.byKey(const Key('amount-setup_fee')), '25000');
      await _tick(tester, 'Additional Service');
      await tester.enterText(find.byKey(const Key('amount-additional_service')), '3000');
      await tester.tap(find.byKey(const Key('add-other-fee')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('other-name-0')), '  Data migration ');
      await tester.enterText(find.byKey(const Key('other-amount-0')), '1500');
      await tester.tap(find.text('Save Payment'));
      await tester.pumpAndSettle();

      final sent = fake.createdItems.single;
      expect([for (final item in sent) item.label], ['Setup Fee', 'Additional Service', 'Data migration']);
      expect([for (final item in sent) item.amount], [25000, 3000, 1500]);
      expect((await fake.list()).single.amount, 29500);
      expect(find.text('Payment recorded.'), findsOneWidget);
    });

    testWidgets('nothing ticked is refused before anything is sent', (tester) async {
      _tall(tester);
      final fake = FakePaymentRepository();
      await tester.pumpWidget(wrap(fake, const AddPaymentDialog()));
      await _open(tester);
      await _chooseSchool(tester);

      await tester.tap(find.text('Save Payment'));
      await tester.pumpAndSettle();

      expect(find.text('Choose at least one service'), findsOneWidget);
      expect(fake.createdItems, isEmpty);
    });

    testWidgets('a ticked service with no amount, and an other fee with no name, are refused', (tester) async {
      _tall(tester);
      final fake = FakePaymentRepository();
      await tester.pumpWidget(wrap(fake, const AddPaymentDialog()));
      await _open(tester);
      await _chooseSchool(tester);

      await _tick(tester, 'Setup Fee');
      await tester.tap(find.byKey(const Key('add-other-fee')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('other-amount-0')), '100');
      await tester.tap(find.text('Save Payment'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount'), findsOneWidget);
      expect(find.text('Say what this fee is for'), findsOneWidget);
      expect(fake.createdItems, isEmpty);
    });

    testWidgets('an other fee can be removed again', (tester) async {
      _tall(tester);
      await tester.pumpWidget(wrap(FakePaymentRepository(), const AddPaymentDialog()));
      await _open(tester);

      await tester.tap(find.byKey(const Key('add-other-fee')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-other-fee')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('other-name-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove-other-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('other-name-1')), findsNothing);
      expect(find.byKey(const Key('other-name-0')), findsOneWidget);
    });

    testWidgets('a quick double tap on Save records the payment once', (tester) async {
      _tall(tester);
      final fake = FakePaymentRepository();
      await tester.pumpWidget(wrap(fake, const AddPaymentDialog()));
      await _open(tester);
      await _chooseSchool(tester);
      await _tick(tester, 'Setup Fee');
      await tester.enterText(find.byKey(const Key('amount-setup_fee')), '100');

      await tester.tap(find.text('Save Payment'));
      await tester.tap(find.text('Save Payment'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(fake.createdItems, hasLength(1));
    });
  });

  group('the Edit Payment form', () {
    final payment = Payment(
      id: 7,
      schoolId: 1,
      schoolName: 'Sunrise Public School',
      paymentType: PaymentType.setupFee,
      items: const [
        PaymentItem(service: PaymentType.setupFee, amount: 25000),
        PaymentItem(service: PaymentType.other, name: 'Staff training day', amount: 5000),
      ],
      amount: 30000,
      paidAmount: 30000,
      remainingAmount: 0,
      currencyCode: 'INR',
      paymentDate: DateTime(2026, 11, 1),
      paymentMode: PaymentMode.bankTransfer,
      referenceNumber: null,
      notes: null,
      status: PaymentStatus.paid,
      createdByName: 'Super Admin',
    );

    testWidgets('opens with the payment\'s services already filled in', (tester) async {
      _tall(tester);
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [payment]), EditPaymentDialog(payment: payment)));
      await _open(tester);

      expect(find.byKey(const Key('amount-setup_fee')), findsOneWidget);
      expect(find.byKey(const Key('amount-annual_maintenance')), findsNothing);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: find.byKey(const Key('other-name-0')), matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Staff training day',
      );
      expect(_total(tester), contains('30,000.00'));
    });

    testWidgets('changing the services sends the new list and the total follows', (tester) async {
      _tall(tester);
      final fake = FakePaymentRepository(payments: [payment]);
      await tester.pumpWidget(wrap(fake, EditPaymentDialog(payment: payment)));
      await _open(tester);

      await tester.tap(find.byKey(const Key('remove-other-0')));
      await tester.pumpAndSettle();
      await _tick(tester, 'Annual Maintenance');
      await tester.enterText(find.byKey(const Key('amount-annual_maintenance')), '8000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = (await fake.list()).single;
      expect([for (final item in saved.items) item.label], ['Setup Fee', 'Annual Maintenance']);
      expect(saved.amount, 33000);
      expect(find.text('Payment updated.'), findsOneWidget);
    });
  });

  group('the list and the receipt', () {
    test('a payment with several services is summed up in one phrase', () {
      final payment = Payment.fromJson({
        'id': 1,
        'school_id': 1,
        'school_name': 'Sunrise Public School',
        'payment_type': 'setup_fee',
        'amount': '30000.00',
        'paid_amount': '30000.00',
        'remaining_amount': '0.00',
        'currency_code': 'INR',
        'payment_date': '2026-11-01',
        'payment_mode': 'cash',
        'status': 'paid',
        'items': [
          {'service': 'setup_fee', 'name': null, 'amount': '25000.00'},
          {'service': 'other', 'name': 'Staff training day', 'amount': '5000.00'},
        ],
      });

      expect(payment.servicesSummary, 'Setup Fee + 1 more');
      expect(payment.items.last.label, 'Staff training day');
    });

    testWidgets('the receipt view lists each service with its amount', (tester) async {
      final payment = Payment(
        id: 1,
        schoolId: 1,
        schoolName: 'Sunrise Public School',
        paymentType: PaymentType.setupFee,
        items: const [
          PaymentItem(service: PaymentType.setupFee, amount: 25000),
          PaymentItem(service: PaymentType.other, name: 'Staff training day', amount: 5000),
        ],
        amount: 30000,
        paidAmount: 30000,
        remainingAmount: 0,
        currencyCode: 'INR',
        paymentDate: DateTime(2026, 11, 1),
        paymentMode: PaymentMode.cash,
        referenceNumber: null,
        notes: null,
        status: PaymentStatus.paid,
        createdByName: 'Super Admin',
      );
      _tall(tester);
      await tester.pumpWidget(wrap(FakePaymentRepository(payments: [payment]), PaymentReceiptDialog(payment: payment)));
      await _open(tester);

      expect(find.text('Setup Fee'), findsOneWidget);
      expect(find.text('Staff training day'), findsOneWidget);
      // Each amount on its own row (25,000 also contains "5,000", hence the anchors).
      expect(find.textContaining(RegExp(r'^\D*5,000\.00$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\D*25,000\.00$')), findsOneWidget);
    });
  });
}
