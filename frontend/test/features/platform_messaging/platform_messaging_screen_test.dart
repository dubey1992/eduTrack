import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/brand_loader.dart';
import 'package:edutrack_app/features/platform_messaging/data/models/platform_messaging.dart';
import 'package:edutrack_app/features/platform_messaging/data/platform_messaging_repository.dart';
import 'package:edutrack_app/features/platform_messaging/presentation/platform_messaging_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_platform_messaging_repository.dart';

Widget wrap(FakePlatformMessagingRepository fake) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [platformMessagingRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: PlatformMessagingScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<FakePlatformMessagingRepository> pumpScreen(WidgetTester tester, [FakePlatformMessagingRepository? fake]) async {
  useDesktop(tester);
  final repository = fake ?? FakePlatformMessagingRepository();
  await tester.pumpWidget(wrap(repository));
  await tester.pumpAndSettle();
  return repository;
}

/// The input of a setting's box; the secret one is inside a PasswordField.
Finder credentialInput(String key) {
  return find.descendant(of: find.byKey(Key('messaging-$key')), matching: find.byType(TextFormField), matchRoot: true);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) => tapVisible(tester, find.byKey(const Key('messaging-save')));

Future<void> chooseProvider(WidgetTester tester, String label) async {
  await tapVisible(tester, find.byKey(const Key('messaging-provider')));
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The number box of the test dialog's phone field (India, 10 digits).
Finder testNumberInput() {
  return find.descendant(of: find.byKey(const Key('messaging-test-to')), matching: find.byType(TextFormField));
}

/// The Super Admin's own SMS and WhatsApp account: shown without its
/// secrets, saved with only what was typed, testable, and its WhatsApp
/// templates mapped event by event.
void main() {
  group('loading', () {
    testWidgets('shows a spinner while the account loads', (tester) async {
      useDesktop(tester);
      final fake = FakePlatformMessagingRepository()..getGate = Completer<void>();
      await tester.pumpWidget(wrap(fake));
      await tester.pump();

      expect(find.byType(BrandLoader), findsOneWidget);
      expect(find.byKey(const Key('messaging-provider')), findsNothing);

      fake.getGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(BrandLoader), findsNothing);
      expect(find.byKey(const Key('messaging-provider')), findsOneWidget);
    });

    testWidgets('a failed load shows the error and retries on request', (tester) async {
      final fake = await pumpScreen(
        tester,
        FakePlatformMessagingRepository(
          failGetWith: const Failure(code: 'FORBIDDEN', message: 'This action is unauthorized.'),
        ),
      );

      expect(find.text('This action is unauthorized.'), findsOneWidget);
      expect(find.byKey(const Key('messaging-provider')), findsNothing);

      fake.failGetWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(fake.getCalls, 2);
      expect(find.byKey(const Key('messaging-provider')), findsOneWidget);
    });
  });

  group('the account', () {
    testWidgets('shows a saved Twilio account without any secret', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Messaging'), findsOneWidget);
      expect(find.textContaining("sends every school's SMS and WhatsApp"), findsOneWidget);
      expect(find.text('Twilio'), findsOneWidget);
      expect(find.text('Last tested 10/28/2026 4:10 PM'), findsOneWidget);
      expect(find.text('Last test succeeded'), findsOneWidget);
      expect(find.text('Updated by Platform Owner'), findsOneWidget);
      expect(find.textContaining('Last test failed'), findsNothing);

      // Nothing stored is put back in a box; each only says what is saved.
      for (final key in ['account_sid', 'auth_token', 'sms_from', 'whatsapp_from']) {
        expect(tester.widget<TextFormField>(credentialInput(key)).controller!.text, isEmpty, reason: key);
      }
      expect(find.text('Saved: …5678 - leave empty to keep'), findsOneWidget);
      expect(find.text('Saved - leave empty to keep'), findsOneWidget);
      expect(find.textContaining('whatsapp:'), findsOneWidget);
    });

    testWidgets('an account never saved is the Demo Gateway, which sends nothing', (tester) async {
      await pumpScreen(tester, FakePlatformMessagingRepository(settings: unsavedPlatformMessaging()));

      expect(find.text('Demo Gateway'), findsOneWidget);
      expect(find.text('Not saved yet - messages go through the Demo Gateway.'), findsOneWidget);
      expect(find.textContaining('records every message and sends nothing'), findsOneWidget);
      expect(find.byKey(const Key('messaging-account_sid')), findsNothing);
      expect(find.textContaining('Last tested'), findsNothing);
      expect(find.textContaining('Updated by'), findsNothing);
    });

    testWidgets('choosing Twilio asks for its settings', (tester) async {
      await pumpScreen(tester, FakePlatformMessagingRepository(settings: unsavedPlatformMessaging()));

      await chooseProvider(tester, 'Twilio');

      expect(find.byKey(const Key('messaging-account_sid')), findsOneWidget);
      expect(find.byKey(const Key('messaging-auth_token')), findsOneWidget);
      expect(find.byKey(const Key('messaging-sms_from')), findsOneWidget);
      expect(find.byKey(const Key('messaging-whatsapp_from')), findsOneWidget);
      expect(find.textContaining('records every message and sends nothing'), findsNothing);
      // Nothing saved yet: nothing to keep, nothing to remove.
      expect(find.textContaining('leave empty to keep'), findsNothing);
      expect(find.textContaining('Remove the saved'), findsNothing);
    });

    testWidgets('a failed last test is shown in full', (tester) async {
      await pumpScreen(
        tester,
        FakePlatformMessagingRepository(settings: platformMessaging(lastTestError: 'Authenticate')),
      );

      expect(find.text('Last test failed: Authenticate'), findsOneWidget);
      expect(find.text('Last test succeeded'), findsNothing);
    });
  });

  group('saving', () {
    testWidgets('sends only what was typed - an empty token box keeps the saved token', (tester) async {
      final fake = await pumpScreen(tester);

      await tester.enterText(credentialInput('sms_from'), '+14155550123');
      await save(tester);

      expect(fake.lastProvider, 'twilio');
      expect(fake.lastCredentials, {'sms_from': '+14155550123'});
      expect(fake.lastCredentials!.containsKey('auth_token'), isFalse);
      expect(find.text('Messaging settings saved.'), findsOneWidget);
      // The box goes back to meaning "keep it".
      expect(tester.widget<TextFormField>(credentialInput('sms_from')).controller!.text, isEmpty);
      expect(find.text('Saved: …0123 - leave empty to keep'), findsOneWidget);
    });

    testWidgets('a typed token is sent, then the box empties again', (tester) async {
      final fake = await pumpScreen(tester, FakePlatformMessagingRepository(settings: unsavedPlatformMessaging()));
      await chooseProvider(tester, 'Twilio');

      await tester.enterText(credentialInput('account_sid'), 'AC00000000000000000000000000001234');
      await tester.enterText(credentialInput('auth_token'), 'top-secret-token');
      await save(tester);

      expect(fake.lastCredentials, {
        'account_sid': 'AC00000000000000000000000000001234',
        'auth_token': 'top-secret-token',
      });
      expect(tester.widget<TextFormField>(credentialInput('auth_token')).controller!.text, isEmpty);
      expect(find.text('Saved - leave empty to keep'), findsOneWidget);
    });

    testWidgets('removing a saved value sends it empty', (tester) async {
      final fake = await pumpScreen(tester);

      await tapVisible(tester, find.byKey(const Key('messaging-clear-whatsapp_from')));
      expect(find.text('The saved value will be removed when you save.'), findsOneWidget);
      expect(find.text('Keep the saved WhatsApp sender number'), findsOneWidget);

      await save(tester);

      expect(fake.lastCredentials, {'whatsapp_from': ''});
      expect(find.byKey(const Key('messaging-clear-whatsapp_from')), findsNothing);
    });

    testWidgets('switching to the Demo Gateway sends no credentials, so the saved ones are kept', (tester) async {
      final fake = await pumpScreen(tester);

      await tester.enterText(credentialInput('sms_from'), '+14155550123');
      await chooseProvider(tester, 'Demo Gateway');
      await save(tester);

      expect(fake.lastProvider, 'log');
      expect(fake.lastCredentials, isEmpty);
    });

    testWidgets('refuses sender numbers not in international form before they reach the server', (tester) async {
      final fake = await pumpScreen(tester);

      await tester.enterText(credentialInput('sms_from'), '4155550123');
      await tester.enterText(credentialInput('whatsapp_from'), 'whatsapp:+14155550199');
      await save(tester);

      expect(
        find.text('Use the full international form, like +14155550123, or a sender ID of up to 11 letters'),
        findsOneWidget,
      );
      expect(find.text('Leave out "whatsapp:" - the app adds it'), findsOneWidget);
      expect(fake.saveCalls, 0);
    });

    testWidgets('an SMS sender may be a registered sender ID; a WhatsApp one may not', (tester) async {
      final fake = await pumpScreen(tester);

      // India's DLT headers are letters, and Twilio sends them as the From.
      await tester.enterText(credentialInput('sms_from'), 'SCHOOL');
      await tester.enterText(credentialInput('whatsapp_from'), 'SCHOOL');
      await save(tester);

      expect(find.text('Use the full international form, like +14155550123'), findsOneWidget);
      expect(fake.saveCalls, 0);

      await tester.enterText(credentialInput('whatsapp_from'), '+14155550199');
      await save(tester);

      expect(fake.saveCalls, 1);
      expect(fake.lastCredentials?['sms_from'], 'SCHOOL');
    });

    testWidgets('a save the server refuses shows its message against the settings', (tester) async {
      final fake = await pumpScreen(
        tester,
        FakePlatformMessagingRepository(
          failSaveWith: const Failure(
            code: 'VALIDATION_ERROR',
            message: 'The account_sid may not be greater than 255 characters.',
            details: {
              'errors': {
                'credentials': ['The account_sid may not be greater than 255 characters.'],
              },
            },
          ),
        ),
      );

      await tester.enterText(credentialInput('account_sid'), 'AC-too-long');
      await save(tester);

      expect(fake.saveCalls, 1);
      // Once as the form's error line, once under the settings it is about.
      expect(find.text('The account_sid may not be greater than 255 characters.'), findsNWidgets(2));
      expect(find.text('Messaging settings saved.'), findsNothing);
      // Still editable, and what was typed is still there.
      expect(tester.widget<TextFormField>(credentialInput('account_sid')).controller!.text, 'AC-too-long');
    });
  });

  group('the test message', () {
    testWidgets('needs a number', (tester) async {
      final fake = await pumpScreen(tester);

      await tapVisible(tester, find.byKey(const Key('messaging-test-sms')));
      expect(find.text('Send test SMS'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      expect(find.text('Send to is required'), findsOneWidget);
      expect(fake.lastTestTo, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('one that goes out closes the dialog and says so', (tester) async {
      final fake = await pumpScreen(tester);

      await tapVisible(tester, find.byKey(const Key('messaging-test-whatsapp')));
      await tester.enterText(testNumberInput(), '9876543210');
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      expect(fake.lastTestChannel, MessagingChannel.whatsapp);
      expect(fake.lastTestTo, '+91 9876543210');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('A test WhatsApp was sent to +91 9876543210.'), findsOneWidget);
      expect(find.text('Last tested 10/29/2026 3:05 PM'), findsOneWidget);
    });

    testWidgets("one the provider refuses stays open in the provider's words", (tester) async {
      final fake = await pumpScreen(
        tester,
        FakePlatformMessagingRepository(
          failTestWith: const Failure(
            code: 'GATEWAY_TEST_FAILED',
            message: "The 'From' number +14155550123 is not a valid phone number.",
          ),
        ),
      );

      await tapVisible(tester, find.byKey(const Key('messaging-test-sms')));
      await tester.enterText(testNumberInput(), '9876543210');
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      expect(fake.lastTestChannel, MessagingChannel.sms);
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text("The 'From' number +14155550123 is not a valid phone number.")),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    });
  });

  group('WhatsApp templates', () {
    testWidgets('lists every event with its mapping, or says it is skipped', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Marked absent'), findsOneWidget);
      expect(find.text('HX0001 · en'), findsOneWidget);
      expect(find.text('Parameters: {{1}} student_name, {{2}} date'), findsOneWidget);
      expect(find.text('Fee reminder'), findsOneWidget);
      expect(find.text('Not mapped — WhatsApp copies of this message are skipped'), findsOneWidget);
      expect(find.byKey(const Key('template-clear-attendance.absent')), findsOneWidget);
      expect(find.byKey(const Key('template-clear-fees.reminder')), findsNothing);
    });

    testWidgets('editing sends the parameters in the order they were chosen', (tester) async {
      final fake = await pumpScreen(tester);

      await tapVisible(tester, find.byKey(const Key('template-edit-attendance.absent')));
      expect(find.text('{{1}} student_name'), findsOneWidget);

      // Take {student_name} out of first place, and put it back last.
      await tester.tap(
        find.descendant(of: find.byKey(const Key('template-parameter-0')), matching: find.byIcon(Icons.close)),
      );
      await tester.pumpAndSettle();
      expect(find.text('{{1}} date'), findsOneWidget);
      await tester.tap(find.byKey(const Key('template-token-school_name')));
      await tester.tap(find.byKey(const Key('template-token-student_name')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('template-sid')), 'HX0002');
      await tester.enterText(find.byKey(const Key('template-language')), 'en_US');
      await tester.tap(find.byKey(const Key('template-save')));
      await tester.pumpAndSettle();

      expect(fake.lastTemplateSave, {
        'event': 'attendance.absent',
        'template_name': 'HX0002',
        'language': 'en_US',
        'parameters': ['date', 'school_name', 'student_name'],
      });
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('WhatsApp template saved.'), findsOneWidget);
      expect(find.text('HX0002 · en_US'), findsOneWidget);
      expect(find.text('Parameters: {{1}} date, {{2}} school_name, {{3}} student_name'), findsOneWidget);
    });

    testWidgets('mapping a new one needs a Content SID and a language code', (tester) async {
      final fake = await pumpScreen(tester);

      await tapVisible(tester, find.byKey(const Key('template-edit-fees.reminder')));
      expect(tester.widget<TextFormField>(find.byKey(const Key('template-language'))).controller!.text, 'en');
      expect(find.text('None chosen - the template has no parameters.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('template-language')), 'English');
      await tester.tap(find.byKey(const Key('template-save')));
      await tester.pumpAndSettle();

      expect(find.text('Content SID is required'), findsOneWidget);
      expect(find.text('Use a code such as en or en_US'), findsOneWidget);
      expect(fake.lastTemplateSave, isNull);

      await tester.enterText(find.byKey(const Key('template-sid')), 'HX0009');
      await tester.enterText(find.byKey(const Key('template-language')), 'en');
      await tester.tap(find.byKey(const Key('template-token-amount')));
      await tester.tap(find.byKey(const Key('template-token-student_name')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template-save')));
      await tester.pumpAndSettle();

      expect(fake.lastTemplateSave!['parameters'], ['amount', 'student_name']);
      expect(find.text('Not mapped — WhatsApp copies of this message are skipped'), findsNothing);
    });

    testWidgets('a template the server refuses stays open with its reason', (tester) async {
      final fake = await pumpScreen(
        tester,
        FakePlatformMessagingRepository(
          failTemplateWith: const Failure(
            code: 'VALIDATION_ERROR',
            message: 'This message can only fill parameters from these placeholders.',
            details: {
              'errors': {
                'parameters': ['This message can only fill parameters from these placeholders.'],
              },
            },
          ),
        ),
      );

      await tapVisible(tester, find.byKey(const Key('template-edit-attendance.absent')));
      await tester.tap(find.byKey(const Key('template-save')));
      await tester.pumpAndSettle();

      expect(fake.lastTemplateSave, isNotNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('This message can only fill parameters from these placeholders.'), findsNWidgets(2));
      expect(find.text('WhatsApp template saved.'), findsNothing);
    });

    testWidgets('clearing asks first, and cancelling keeps the mapping', (tester) async {
      final fake = await pumpScreen(tester);

      await tapVisible(tester, find.byKey(const Key('template-clear-attendance.absent')));
      expect(find.text('Clear template'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(fake.lastTemplateCleared, isNull);
      expect(find.text('HX0001 · en'), findsOneWidget);
    });

    testWidgets('clearing once confirmed leaves the event unmapped', (tester) async {
      final fake = await pumpScreen(tester);

      await tapVisible(tester, find.byKey(const Key('template-clear-attendance.absent')));
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();

      expect(fake.lastTemplateCleared, 'attendance.absent');
      expect(find.text('WhatsApp template cleared.'), findsOneWidget);
      expect(find.text('HX0001 · en'), findsNothing);
      expect(find.text('Not mapped — WhatsApp copies of this message are skipped'), findsNWidgets(2));
    });
  });

  testWidgets('fits a phone: nothing overflows', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(FakePlatformMessagingRepository()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('messaging-provider')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('template-edit-fees.reminder')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
