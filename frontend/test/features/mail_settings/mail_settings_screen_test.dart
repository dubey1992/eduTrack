import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/mail_settings/data/mail_settings_repository.dart';
import 'package:edutrack_app/features/mail_settings/presentation/mail_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_mail_settings_repository.dart';

Widget wrap(FakeMailSettingsRepository fake) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [mailSettingsRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: MailSettingsScreen()),
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

String fieldText(WidgetTester tester, Key key) {
  return tester.widget<TextFormField>(find.byKey(key)).controller!.text;
}

/// The password field is the shared PasswordField; its input is inside it.
Finder passwordInput() {
  return find.descendant(of: find.byKey(const Key('mail-password')), matching: find.byType(TextFormField));
}

Future<void> openTestDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Send test email'));
  await tester.pumpAndSettle();
}

/// The Super Admin's SMTP settings: shown as saved (or as the server's
/// fallback), checked before they are sent, and testable without saving a
/// password the form never learns.
void main() {
  testWidgets('shows a spinner while the settings load', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository()..getGate = Completer<void>();
    await tester.pumpWidget(wrap(fake));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('mail-host')), findsNothing);

    fake.getGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('mail-host')), findsOneWidget);
  });

  testWidgets('a failed load shows the error and retries on request', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository(
      failGetWith: const Failure(code: 'FORBIDDEN', message: 'Only a Super Admin can do this.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Only a Super Admin can do this.'), findsOneWidget);
    expect(find.byKey(const Key('mail-host')), findsNothing);

    fake.failGetWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fake.getCalls, 2);
    expect(fieldText(tester, const Key('mail-host')), 'smtp.example.com');
  });

  testWidgets('renders the saved settings and where they come from', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeMailSettingsRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Email Settings'), findsOneWidget);
    expect(fieldText(tester, const Key('mail-host')), 'smtp.example.com');
    expect(fieldText(tester, const Key('mail-port')), '587');
    expect(fieldText(tester, const Key('mail-username')), 'mailer');
    expect(fieldText(tester, const Key('mail-from-address')), 'no-reply@example.com');
    expect(fieldText(tester, const Key('mail-from-name')), 'School365ai');
    expect(find.text('STARTTLS (tls)'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('mail-is-active'))).value, isTrue);
    // The password never comes back; the field only knows one is stored.
    expect(tester.widget<TextFormField>(passwordInput()).controller!.text, isEmpty);
    expect(find.text('Leave blank to keep the saved password'), findsOneWidget);
    expect(find.text('Source: database'), findsOneWidget);
    expect(find.text('Last tested 09/18/2026 4:10 PM'), findsOneWidget);
    expect(find.text('Updated by Platform Owner'), findsOneWidget);
    expect(find.textContaining('Last test failed'), findsNothing);
  });

  testWidgets('the environment fallback is shown as such, with no password to keep', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeMailSettingsRepository(settings: environmentMailSettings())));
    await tester.pumpAndSettle();

    expect(find.text('Source: environment'), findsOneWidget);
    expect(fieldText(tester, const Key('mail-host')), 'localhost');
    expect(fieldText(tester, const Key('mail-port')), '25');
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('mail-is-active'))).value, isFalse);
    expect(find.text('Leave blank to keep the saved password'), findsNothing);
    expect(find.text('Remove the saved password'), findsNothing);
    expect(find.textContaining('Last tested'), findsNothing);
    expect(find.textContaining('Updated by'), findsNothing);
  });

  testWidgets('a failed last test is shown in full', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(FakeMailSettingsRepository(settings: mailSettings(lastTestError: 'Authentication failed'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Last test failed: Authentication failed'), findsOneWidget);
  });

  testWidgets('refuses bad values before they reach the server', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mail-host')), '');
    await tester.enterText(find.byKey(const Key('mail-port')), '70000');
    await tester.enterText(find.byKey(const Key('mail-from-address')), 'not-an-address');
    await tester.enterText(find.byKey(const Key('mail-from-name')), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Host is required'), findsOneWidget);
    expect(find.text('Port must be between 1 and 65535'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('From name is required'), findsOneWidget);
    expect(fake.saveCalls, 0);

    await tester.enterText(find.byKey(const Key('mail-from-address')), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('From address is required'), findsOneWidget);
    expect(fake.saveCalls, 0);
  });

  testWidgets('saving sends the form and leaves an untouched password out', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mail-host')), 'smtp.new.example.com');
    await tester.enterText(find.byKey(const Key('mail-port')), '465');
    await tester.enterText(find.byKey(const Key('mail-username')), '');
    await tester.enterText(find.byKey(const Key('mail-from-address')), 'alerts@example.com');
    await tester.enterText(find.byKey(const Key('mail-from-name')), 'Alerts');
    await tester.tap(find.byKey(const Key('mail-encryption')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSL').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mail-is-active')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fake.lastSave, {
      'is_active': false,
      'host': 'smtp.new.example.com',
      'port': 465,
      'encryption': 'ssl',
      'username': null,
      'password': null,
      'from_address': 'alerts@example.com',
      'from_name': 'Alerts',
    });
    expect(find.text('Email settings saved.'), findsOneWidget);
    expect(find.text('Updated by Platform Owner'), findsOneWidget);
  });

  testWidgets('a typed password is sent, then the field goes back to keeping it', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository(settings: mailSettings(passwordSet: false));
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    expect(find.text('Leave blank to keep the saved password'), findsNothing);

    await tester.enterText(passwordInput(), 'new-secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fake.lastSave!['password'], 'new-secret');
    expect(tester.widget<TextFormField>(passwordInput()).controller!.text, isEmpty);
    expect(find.text('Leave blank to keep the saved password'), findsOneWidget);
  });

  testWidgets('removing the saved password sends an empty one', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mail-clear-password')));
    await tester.pumpAndSettle();
    expect(find.text('The saved password will be removed when you save.'), findsOneWidget);
    expect(find.text('Keep the saved password'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(fake.lastSave!['password'], '');
    expect(find.text('Leave blank to keep the saved password'), findsNothing);
    expect(find.text('Remove the saved password'), findsNothing);
  });

  testWidgets('a save the server refuses shows its message against the field', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository(
      failSaveWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The from address field must be a valid email address.',
        details: {
          'errors': {
            'from_address': ['The from address field must be a valid email address.'],
          },
        },
      ),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Once as the form's error line, once under the field it is about.
    expect(find.text('The from address field must be a valid email address.'), findsNWidgets(2));
    expect(find.text('Email settings saved.'), findsNothing);
    // Still editable: the form did not fall into the screen's error state.
    expect(find.byKey(const Key('mail-host')), findsOneWidget);
  });

  testWidgets('the test dialog refuses a bad address', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await openTestDialog(tester);
    await tester.enterText(find.byKey(const Key('mail-test-to')), 'nope');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(fake.lastTestTo, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('a test email that goes out closes the dialog and says so', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await openTestDialog(tester);
    await tester.enterText(find.byKey(const Key('mail-test-to')), 'ops@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(fake.lastTestTo, 'ops@example.com');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('A test email was sent to ops@example.com.'), findsOneWidget);
    // The status line picks up the test that just happened.
    expect(find.text('Last tested 09/19/2026 11:00 AM'), findsOneWidget);
  });

  testWidgets('a test the server could not send stays open with the reason', (tester) async {
    useDesktop(tester);
    final fake = FakeMailSettingsRepository(
      failTestWith: const Failure(code: 'MAIL_TEST_FAILED', message: 'Connection refused by smtp.example.com:587'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await openTestDialog(tester);
    await tester.enterText(find.byKey(const Key('mail-test-to')), 'ops@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(fake.lastTestTo, 'ops@example.com');
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Connection refused by smtp.example.com:587')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('fits a phone: the fields stack and nothing overflows', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(FakeMailSettingsRepository()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('mail-host')), findsOneWidget);
    expect(find.byKey(const Key('mail-port')), findsOneWidget);
  });
}
