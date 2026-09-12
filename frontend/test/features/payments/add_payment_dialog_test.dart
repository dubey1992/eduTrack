import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/payments/data/payment_repository.dart';
import 'package:edutrack_app/features/payments/presentation/add_payment_dialog.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payment_repository.dart';
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

Widget wrap(FakePaymentRepository fake, {List<School> schools = const [_school]}) {
  return ProviderScope(
    overrides: [
      paymentRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: schools)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const AddPaymentDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _selectSchoolAndAmount(WidgetTester tester, {String amount = '2500'}) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'School'));
  await tester.pumpAndSettle();
  // The dropdown item combines the school name with its currency (see
  // AddPaymentDialog's School DropdownMenuItem), so match on that combined
  // label rather than the bare school name.
  await tester.tap(find.text('Sunrise Public School (INR)').last);
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), amount);
}

void main() {
  testWidgets('shows validation errors when the school and amount are missing', (tester) async {
    await tester.pumpWidget(wrap(FakePaymentRepository()));
    await _openDialog(tester);

    await tester.tap(find.text('Save Payment'));
    await tester.pumpAndSettle();

    expect(find.text('School is required'), findsOneWidget);
    expect(find.text('Enter a valid amount'), findsOneWidget);
  });

  testWidgets('creates the payment, closes the dialog, and shows a confirmation snackbar', (tester) async {
    final fake = FakePaymentRepository();
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await _selectSchoolAndAmount(tester);
    await tester.tap(find.text('Save Payment'));
    await tester.pumpAndSettle();

    final created = await fake.list();
    expect(created, hasLength(1));
    expect(created.single.schoolId, 1);
    expect(created.single.amount, 2500);
    expect(find.byType(AddPaymentDialog), findsNothing);
    expect(find.text('Payment recorded.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open when the repository throws', (tester) async {
    final fake = FakePaymentRepository(
      failCreateWith: const Failure(code: 'PAYMENT_CREATE_FAILED', message: 'Could not record the payment.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await _selectSchoolAndAmount(tester);
    await tester.tap(find.text('Save Payment'));
    await tester.pumpAndSettle();

    expect(find.text('Could not record the payment.'), findsOneWidget);
    expect(find.byType(AddPaymentDialog), findsOneWidget);
  });
}
