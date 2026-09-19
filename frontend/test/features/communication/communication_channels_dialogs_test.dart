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
    testWidgets('shows the WhatsApp, Email and provider account sections', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Enable WhatsApp')).value, isTrue);
      expect(find.widgetWithText(DropdownButtonFormField<String>, 'Meta WhatsApp Cloud API'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Enable email')).value, isTrue);
      expect(
        find.text('No SMTP server is set up yet. The Super Admin can add one under Email Settings.'),
        findsOneWidget,
      );

      // Twilio carries SMS and Meta carries WhatsApp, so both accounts are asked for.
      expect(find.text('Provider accounts'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Account SID'), findsOneWidget);
      expect(find.text('On file: …5678'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Auth token'), findsOneWidget);
      expect(find.text('Saved - leave blank to keep'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'SMS sender number'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Phone number ID'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Access token'), findsOneWidget);

      // Boxes are never prefilled: the value is not sent back, only its status.
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Account SID')).controller!.text, '');
      // A secret is obscured; a plain field is not.
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.widgetWithText(TextFormField, 'Auth token'),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isTrue,
      );
    });

    testWidgets('with the demo gateways there are no account boxes and the test buttons are off', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('The chosen gateways need no account details.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Account SID'), findsNothing);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Send test SMS')).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Send test WhatsApp')).onPressed,
        isNull,
      );
    });

    testWidgets('choosing a real gateway reveals its account boxes', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Demo Gateway').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Twilio').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Account SID'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Phone number ID'), findsNothing);
      // Nothing is on file yet, so there is nothing to clear.
      expect(find.byTooltip('Clear Account SID'), findsNothing);
    });

    testWidgets('saving sends the channel switches and only the credentials that were typed', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.widgetWithText(SwitchListTile, 'Enable email'));
      await tester.enterText(find.widgetWithText(TextFormField, 'SMS sender number'), '+15550001111');
      await tester.enterText(find.widgetWithText(TextFormField, 'Access token'), 'EAAB-secret');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save Settings'));

      expect(fake.lastCall!['op'], 'updateSettings');
      expect(fake.lastCall!['whatsapp_enabled'], isTrue);
      expect(fake.lastCall!['whatsapp_provider'], 'meta');
      expect(fake.lastCall!['email_enabled'], isFalse);
      expect(fake.lastCall!['credentials'], {
        'twilio': {'sms_from': '+15550001111'},
        'meta': {'access_token': 'EAAB-secret'},
      });
      expect(find.text('Alert settings saved.'), findsOneWidget);

      // The boxes empty out and now say what is on file.
      expect(
        tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'SMS sender number')).controller!.text,
        '',
      );
      expect(find.text('On file: …1111'), findsOneWidget);
      expect(find.text('Saved - leave blank to keep'), findsNWidgets(2));
    });

    testWidgets('clearing a saved credential sends an empty value, and can be undone', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.byTooltip('Clear Auth token'));
      expect(find.text('Will be cleared when you save.'), findsOneWidget);

      await tapVisible(tester, find.byTooltip('Keep Auth token'));
      expect(find.text('Will be cleared when you save.'), findsNothing);

      await tapVisible(tester, find.byTooltip('Clear Account SID'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save Settings'));

      expect(fake.lastCall!['credentials'], {
        'twilio': {'account_sid': ''},
      });
      expect(find.text('On file: …5678'), findsNothing);
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

  group('MessageTemplatesDialog WhatsApp section', () {
    testWidgets('says which events are mapped and which are not', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('WhatsApp template'), findsNWidgets(3));
      expect(find.text('Not mapped'), findsNWidgets(2));
      expect(find.text('school_notice (en)'), findsOneWidget);
      expect(find.text('Written by hand'), findsOneWidget);
    });

    testWidgets('saving sends the template name, language and parameters in order', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('WhatsApp template').first);
      expect(
        find.text('WhatsApp only delivers templates approved by your provider; map each message to one.'),
        findsOneWidget,
      );

      await tester.enterText(find.widgetWithText(TextFormField, 'Template name'), 'absent_alert');
      await tapVisible(tester, find.widgetWithText(ActionChip, '{date}'));
      await tapVisible(tester, find.widgetWithText(ActionChip, '{student_name}'));
      expect(find.text('1. {date}'), findsOneWidget);
      expect(find.text('2. {student_name}'), findsOneWidget);

      // Taking the first one out moves the other up.
      await tapVisible(
        tester,
        find.descendant(of: find.widgetWithText(InputChip, '1. {date}'), matching: find.byTooltip('Delete')),
      );
      expect(find.text('1. {student_name}'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(ActionChip, '{date}'));

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save mapping'));

      expect(fake.lastCall, {
        'op': 'setWhatsappTemplate',
        'event': 'attendance.absent',
        'school_id': 1,
        'template_name': 'absent_alert',
        'language': 'en',
        'parameters': ['student_name', 'date'],
      });
      expect(find.text('WhatsApp template for Marked absent saved.'), findsOneWidget);
      expect(find.text('absent_alert (en)'), findsOneWidget);
      expect(find.text('Not mapped'), findsOneWidget);
    });

    testWidgets('an empty template name or a bad language code is refused before it reaches the server', (
      tester,
    ) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('WhatsApp template').first);
      await tester.enterText(find.widgetWithText(TextFormField, 'Language'), 'English');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save mapping'));

      expect(find.text('Enter the template name your provider approved.'), findsOneWidget);
      expect(find.text('Use a code such as en or en_US.'), findsOneWidget);
      expect(fake.lastCall, isNull);
    });

    testWidgets('clearing drops the mapping', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('WhatsApp template').at(2));
      expect(find.text('1. {subject}'), findsOneWidget);
      expect(find.text('2. {body}'), findsOneWidget);

      await tapVisible(tester, find.widgetWithText(TextButton, 'Clear mapping'));

      expect(fake.lastCall, {'op': 'clearWhatsappTemplate', 'event': 'general.message', 'school_id': 1});
      expect(find.text('WhatsApp template for Message cleared.'), findsOneWidget);
      expect(find.text('school_notice (en)'), findsNothing);
      expect(find.text('Not mapped'), findsNWidgets(3));
    });

    testWidgets('a server rejection is shown in the section', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('WhatsApp template').first);
      await tester.enterText(find.widgetWithText(TextFormField, 'Template name'), 'absent_alert');
      fake.failWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'This message can only fill parameters from these placeholders: {student_name}.',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save mapping'));

      expect(
        find.text('This message can only fill parameters from these placeholders: {student_name}.'),
        findsOneWidget,
      );
    });
  });
}
