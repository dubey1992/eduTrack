import 'package:dio/dio.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/demo_requests/data/demo_request_api.dart';
import 'package:edutrack_app/features/demo_requests/data/demo_request_repository.dart';
import 'package:edutrack_app/features/marketing/presentation/widgets/demo_request_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Remembers what the form sent, or refuses it.
class _FakeDemoRequestRepository extends DemoRequestRepository {
  _FakeDemoRequestRepository({this.refuseWith}) : super(DemoRequestApi(Dio()));

  final Failure? refuseWith;
  Map<String, dynamic>? submitted;

  @override
  Future<String> submit(Map<String, dynamic> payload) async {
    if (refuseWith != null) throw refuseWith!;
    submitted = payload;

    return 'Thanks - we will be in touch to confirm a time for your demo.';
  }
}

/// The marketing page's "Request a Demo" form (decided 2026-10-29).
void main() {
  Widget wrap(_FakeDemoRequestRepository fake) {
    return ProviderScope(
      overrides: [demoRequestRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                TextButton(onPressed: () => showDemoRequestDialog(context), child: const Text('Open the form')),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, _FakeDemoRequestRepository fake) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open the form'));
    await tester.pumpAndSettle();
  }

  Future<void> pickADay(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextFormField, 'Preferred day'));
    await tester.pumpAndSettle();
    // The picker opens on tomorrow, which is always allowed.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Priya Nair');
    await tester.enterText(find.widgetWithText(TextFormField, 'School name'), 'Greenfield High');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'priya@greenfield.test');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '9876543210');
    await tester.enterText(find.widgetWithText(TextFormField, 'Country'), 'India');
    await pickADay(tester);
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Request demo'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks who they are and when suits them', (tester) async {
    await open(tester, _FakeDemoRequestRepository());

    expect(find.text('Request a Demo'), findsOneWidget);
    for (final label in [
      'Your name',
      'School name',
      'Email',
      'City (optional)',
      'Country',
      'Roughly how many students? (optional)',
      'Preferred day',
      'What would you like to see? (optional)',
    ]) {
      expect(find.widgetWithText(TextFormField, label), findsOneWidget, reason: '$label is missing');
    }
    expect(find.text('Time of day (optional)'), findsOneWidget);
  });

  testWidgets('will not send without the essentials, the day among them', (tester) async {
    final fake = _FakeDemoRequestRepository();
    await open(tester, fake);

    await send(tester);

    expect(find.text('Your name is required'), findsOneWidget);
    expect(find.text('Country is required'), findsOneWidget);
    expect(find.text('Pick a day for the demo'), findsOneWidget);
    expect(fake.submitted, isNull);
  });

  testWidgets('checks an email looks like one', (tester) async {
    final fake = _FakeDemoRequestRepository();
    await open(tester, fake);
    await fillRequired(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not-an-email');

    await send(tester);

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(fake.submitted, isNull);
  });

  testWidgets('sends the day as a date and the part of the day the server knows', (tester) async {
    final fake = _FakeDemoRequestRepository();
    await open(tester, fake);
    await fillRequired(tester);
    await tester.tap(find.text('Any time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afternoon').last);
    await tester.pumpAndSettle();

    await send(tester);

    final sent = fake.submitted!;
    expect(sent['preferred_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(sent['preferred_time'], 'afternoon');
    expect(sent['school_name'], 'Greenfield High');
    expect(sent['phone'], startsWith('+'));
    // The optional parts go as nothing rather than as empty text.
    expect((sent['city'], sent['message'], sent['expected_students']), (null, null, null));
    // Not a browser here, so no timezone to send.
    expect(sent['timezone'], isNull);
  });

  testWidgets('thanks them afterwards', (tester) async {
    await open(tester, _FakeDemoRequestRepository());
    await fillRequired(tester);

    await send(tester);

    expect(find.text('Demo requested'), findsOneWidget);
    expect(find.text('Thanks - we will be in touch to confirm a time for your demo.'), findsOneWidget);
  });

  testWidgets('keeps what was typed when the server says no', (tester) async {
    final fake = _FakeDemoRequestRepository(
      refuseWith: const Failure(code: 'VALIDATION_ERROR', message: 'Pick a day within the next six months.'),
    );
    await open(tester, fake);
    await fillRequired(tester);

    await send(tester);

    expect(find.text('Pick a day within the next six months.'), findsOneWidget);
    expect(find.text('Greenfield High'), findsOneWidget);
  });
}
