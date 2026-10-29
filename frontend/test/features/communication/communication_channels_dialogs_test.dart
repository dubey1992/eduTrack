import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/communication/data/communication_repository.dart';
import 'package:edutrack_app/features/communication/presentation/communication_settings_dialog.dart';
import 'package:edutrack_app/features/communication/presentation/message_templates_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/communication_fixtures.dart';
import '../../support/fake_communication_repository.dart';

Widget wrap(FakeCommunicationRepository fake, Widget dialog) {
  return ProviderScope(
    overrides: [communicationRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Builder(builder: (context) => dialog)),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('CommunicationSettingsDialog channels', () {
    testWidgets("says messages go through School365ai and shows only the school's switches", (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(find.textContaining('SMS and WhatsApp are sent through School365ai'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Enable WhatsApp')).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Enable email')).value, isTrue);
      expect(
        find.text('No SMTP server is set up yet. The Super Admin can add one under Email Settings.'),
        findsOneWidget,
      );

      // The account is School365ai's (docs/platform-messaging.md): nothing to choose or fill in.
      expect(find.text('SMS Provider'), findsNothing);
      expect(find.text('WhatsApp Provider'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Account SID'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Sender ID (optional)'), findsNothing);
    });

    testWidgets('before School365ai is sending, the school is told and the test buttons are off', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(find.textContaining('School365ai is still setting up SMS and WhatsApp'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Send test SMS')).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Send test WhatsApp')).onPressed,
        isNull,
      );
    });

    testWidgets('saving sends the channel switches and nothing about who carries them', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.widgetWithText(SwitchListTile, 'Enable WhatsApp'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save Settings'));

      expect(fake.lastCall!['whatsapp_enabled'], isFalse);
      expect(fake.lastCall!['email_enabled'], isTrue);
      expect(fake.lastCall!.keys, isNot(contains('provider')));
      expect(fake.lastCall!.keys, isNot(contains('credentials')));
      expect(find.text('Alert settings saved.'), findsOneWidget);
    });

    testWidgets('a test SMS asks for a number and reports what the server said', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Send test SMS'));
      expect(find.text('Send test SMS'), findsNWidgets(2));

      // An empty number never reaches the server.
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the number to send the test to.'), findsOneWidget);
      expect(fake.lastCall, isNull);

      await tester.enterText(find.widgetWithText(TextFormField, 'Mobile number'), '+91 9000000000');
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {'op': 'testGateway', 'school_id': 1, 'channel': 'sms', 'to': '+91 9000000000'});
      expect(find.text('A test message was sent to +91 9000000000.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Mobile number'), findsNothing);
    });

    testWidgets('a refused test is shown inside the dialog, which stays open', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Send test WhatsApp'));
      fake.failWith = const Failure(
        code: 'GATEWAY_TEST_FAILED',
        message: 'Map a WhatsApp template to the Message event first.',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Mobile number'), '+91 9000000000');
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, isNull);
      expect(find.text('Map a WhatsApp template to the Message event first.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Mobile number'), findsOneWidget);
    });
  });

  group('MessageTemplatesDialog WhatsApp line', () {
    testWidgets('says which messages can go by WhatsApp, and offers nothing to map', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      // School365ai maps the templates for every school (docs/platform-messaging.md).
      expect(find.text('WhatsApp: ready, through School365ai.'), findsOneWidget);
      expect(
        find.text('WhatsApp: not available for this message yet - SMS and email copies still go out.'),
        findsNWidgets(2),
      );
      expect(find.text('WhatsApp template'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Template name'), findsNothing);
    });
  });
}
