import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/communication/application/message_page_notifier.dart';
import 'package:edutrack_app/features/communication/application/template_notifier.dart';
import 'package:edutrack_app/features/communication/data/communication_repository.dart';
import 'package:edutrack_app/features/communication/data/models/message.dart';
import 'package:edutrack_app/features/communication/presentation/communication_screen.dart';
import 'package:edutrack_app/features/communication/presentation/send_notice_dialog.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/communication_fixtures.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_communication_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeCommunicationRepository fake) {
  return ProviderScope(
    overrides: [
      communicationRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: CommunicationScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  ProviderContainer makeContainer(FakeCommunicationRepository fake) {
    final container = ProviderContainer(
      overrides: [communicationRepositoryProvider.overrideWithValue(fake)],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  group('models', () {
    test('a channel list is written and read in API order', () {
      expect(
        MessageChannel.joined({MessageChannel.email, MessageChannel.inApp, MessageChannel.sms}),
        'sms,in_app,email',
      );
      expect(MessageChannel.parseJoined('whatsapp, sms,fax'), [MessageChannel.sms, MessageChannel.whatsapp]);
      expect(MessageChannel.joined(const []), '');
    });

    test('settings from an older server still read, with the new channels off', () {
      final settings = CommunicationSettings.fromJson({
        'school_id': 1,
        'sms_enabled': true,
        'attendance_alerts': 'absent',
        'transport_alerts_enabled': true,
        'leave_alerts_enabled': true,
        'provider': 'log',
        'provider_label': 'Demo Gateway',
        'sender_id': null,
        'available_providers': [
          {'value': 'log', 'label': 'Demo Gateway'},
        ],
        'is_saved': true,
      });

      expect(settings.whatsappEnabled, isFalse);
      expect(settings.emailEnabled, isFalse);
      expect(settings.credentialFields, isEmpty);
      expect(settings.enabledChannels, [MessageChannel.sms, MessageChannel.inApp]);
      expect(settings.statusOf('twilio', 'auth_token').isSet, isFalse);
    });

    test('settings carry which credentials are on file, never their values', () {
      final settings = CommunicationSettings.fromJson({
        'school_id': 1,
        'sms_enabled': false,
        'attendance_alerts': 'both',
        'transport_alerts_enabled': true,
        'leave_alerts_enabled': true,
        'provider': 'twilio',
        'provider_label': 'Twilio',
        'provider_delivers': true,
        'sender_id': null,
        'available_providers': [
          {'value': 'twilio', 'label': 'Twilio'},
        ],
        'whatsapp_enabled': true,
        'whatsapp_provider': 'meta',
        'whatsapp_provider_label': 'Meta WhatsApp Cloud API',
        'whatsapp_provider_delivers': true,
        'available_whatsapp_providers': [
          {'value': 'meta', 'label': 'Meta WhatsApp Cloud API'},
        ],
        'email_enabled': true,
        'email_delivers': false,
        'credential_fields': {
          'twilio': [
            {'key': 'account_sid', 'label': 'Account SID', 'secret': false},
            {'key': 'auth_token', 'label': 'Auth token', 'secret': true},
          ],
        },
        'credentials': {
          'twilio': {
            'account_sid': {'set': true, 'hint': '…5678'},
            'auth_token': {'set': true, 'hint': null},
          },
        },
        'is_saved': true,
      });

      expect(settings.enabledChannels, [MessageChannel.inApp, MessageChannel.whatsapp, MessageChannel.email]);
      expect(settings.credentialFields['twilio']!.map((f) => f.key), ['account_sid', 'auth_token']);
      expect(settings.credentialFields['twilio']![1].secret, isTrue);
      expect(settings.statusOf('twilio', 'account_sid').hint, '…5678');
      expect(settings.statusOf('twilio', 'auth_token').hint, isNull);
      expect(settings.emailDelivers, isFalse);
    });

    test('a template reads its WhatsApp mapping, or none', () {
      final mapped = MessageTemplate.fromJson({
        'event': 'general.message',
        'event_label': 'Message',
        'category': 'general',
        'channels': ['sms', 'in_app', 'whatsapp', 'email'],
        'body': '{school_name}: {subject} - {body}',
        'default_body': '{school_name}: {subject} - {body}',
        'is_custom': false,
        'is_manual': true,
        'tokens': ['school_name', 'subject', 'body'],
        'whatsapp': {
          'template_name': 'school_notice',
          'language': 'en',
          'parameters': ['subject', 'body'],
          'updated_at': null,
        },
        'updated_at': null,
        'updated_by_name': null,
      });
      expect(mapped.isManual, isTrue);
      expect(mapped.category, MessageCategory.general);
      expect(mapped.channels, MessageChannel.values);
      expect(mapped.whatsapp!.templateName, 'school_notice');
      expect(mapped.whatsapp!.parameters, ['subject', 'body']);

      final plain = MessageTemplate.fromJson({
        'event': 'attendance.absent',
        'event_label': 'Marked absent',
        'category': 'attendance',
        'channels': ['sms'],
        'body': 'x',
        'default_body': 'x',
        'is_custom': false,
        'tokens': ['student_name'],
        'updated_by_name': null,
      });
      expect(plain.isManual, isFalse);
      expect(plain.whatsapp, isNull);
    });

    test('a notice result reads its per-channel counts and messages', () {
      final result = NoticeResult.fromJson({
        'recipients': 3,
        'by_channel': {'sms': 3, 'in_app': 0, 'whatsapp': 2, 'email': 1},
        'channels': ['sms', 'whatsapp', 'email'],
        'audience_label': 'Grade 8 A',
        'queued': true,
        'messages': [],
      });

      expect(result.recipients, 3);
      expect(result.countFor(MessageChannel.whatsapp), 2);
      expect(result.countFor(MessageChannel.inApp), 0);
      expect(result.channels, [MessageChannel.sms, MessageChannel.whatsapp, MessageChannel.email]);
      expect(result.queued, isTrue);
      expect(result.messages, isEmpty);

      final message = Message.fromJson({
        'id': 1,
        'school_id': 1,
        'event': 'fee.reminder',
        'event_label': 'Fee reminder',
        'category': 'fee',
        'channel': 'email',
        'recipient_name': 'Raj Kumar',
        'recipient_mobile': null,
        'recipient_email': 'raj@example.com',
        'student_id': 7,
        'student_name': 'Arjun Kumar',
        'subject': 'Fee reminder',
        'body': 'Due.',
        'status': 'queued',
        'provider': null,
        'provider_label': null,
        'failure_reason': null,
        'sent_at': null,
        'read_at': null,
        'created_at': null,
        'created_at_label': null,
        'created_on_label': null,
        'sent_at_label': null,
      });
      expect(message.channel, MessageChannel.email);
      expect(message.category, MessageCategory.fee);
      expect(message.recipientEmail, 'raj@example.com');
    });

    test('the notice query compares by value so the preview is not re-fetched for the same form', () {
      const a = NoticeQuery(
        kind: NoticeKind.message,
        audienceType: NoticeAudience.teachers,
        channels: [MessageChannel.sms, MessageChannel.inApp],
        schoolId: 1,
      );
      const b = NoticeQuery(
        kind: NoticeKind.message,
        audienceType: NoticeAudience.teachers,
        channels: [MessageChannel.inApp, MessageChannel.sms],
        schoolId: 1,
      );
      const c = NoticeQuery(
        kind: NoticeKind.message,
        audienceType: NoticeAudience.teachers,
        channels: [MessageChannel.sms],
        schoolId: 1,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('TemplateNotifier WhatsApp', () {
    test('mapping an event records the ordered parameters and shows in the list', () async {
      final fake = FakeCommunicationRepository();
      final container = makeContainer(fake);
      await container.read(templateNotifierProvider(1).future);

      await container
          .read(templateNotifierProvider(1).notifier)
          .saveWhatsapp(
            'attendance.absent',
            templateName: 'absent_alert',
            language: 'en_US',
            parameters: ['date', 'student_name'],
          );

      expect(fake.lastCall, {
        'op': 'setWhatsappTemplate',
        'event': 'attendance.absent',
        'school_id': 1,
        'template_name': 'absent_alert',
        'language': 'en_US',
        'parameters': ['date', 'student_name'],
      });
      final absent = container
          .read(templateNotifierProvider(1))
          .value!
          .firstWhere((t) => t.event == 'attendance.absent');
      expect(absent.whatsapp!.templateName, 'absent_alert');
      expect(absent.whatsapp!.parameters, ['date', 'student_name']);
    });

    test('clearing drops the mapping', () async {
      final fake = FakeCommunicationRepository();
      final container = makeContainer(fake);
      await container.read(templateNotifierProvider(1).future);

      await container.read(templateNotifierProvider(1).notifier).clearWhatsapp('general.message');

      expect(fake.lastCall, {'op': 'clearWhatsappTemplate', 'event': 'general.message', 'school_id': 1});
      final general = container
          .read(templateNotifierProvider(1))
          .value!
          .firstWhere((t) => t.event == 'general.message');
      expect(general.whatsapp, isNull);
    });
  });

  group('CommunicationSettingsNotifier channels', () {
    test('saves the channel switches and only the credentials handed to it', () async {
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      final container = makeContainer(fake);
      await container.read(communicationSettingsNotifierProvider(1).future);

      await container
          .read(communicationSettingsNotifierProvider(1).notifier)
          .save(
            smsEnabled: true,
            attendanceAlerts: AttendanceAlertMode.absentOnly,
            transportAlertsEnabled: true,
            leaveAlertsEnabled: true,
            provider: 'twilio',
            whatsappEnabled: false,
            whatsappProvider: 'twilio',
            emailEnabled: true,
            credentials: {
              'twilio': {'whatsapp_from': '+15550002222', 'auth_token': ''},
            },
          );

      expect(fake.lastCall!['whatsapp_enabled'], isFalse);
      expect(fake.lastCall!['whatsapp_provider'], 'twilio');
      expect(fake.lastCall!['email_enabled'], isTrue);
      expect(fake.lastCall!['credentials'], {
        'twilio': {'whatsapp_from': '+15550002222', 'auth_token': ''},
      });

      final saved = container.read(communicationSettingsNotifierProvider(1)).value!;
      expect(saved.whatsappEnabled, isFalse);
      expect(saved.emailEnabled, isTrue);
      expect(saved.statusOf('twilio', 'whatsapp_from').hint, '…2222');
      expect(saved.statusOf('twilio', 'auth_token').isSet, isFalse);
      // Untouched ones stay as they were.
      expect(saved.statusOf('twilio', 'account_sid').hint, '…5678');
    });

    test('a test message goes through the school and returns the confirmation', () async {
      final fake = FakeCommunicationRepository(settings: twilioSettings, testConfirmation: 'Sent to +91 9000000000.');
      final container = makeContainer(fake);
      await container.read(communicationSettingsNotifierProvider(1).future);

      final confirmation = await container
          .read(communicationSettingsNotifierProvider(1).notifier)
          .sendTest(channel: MessageChannel.whatsapp, to: '+91 9000000000');

      expect(confirmation, 'Sent to +91 9000000000.');
      expect(fake.lastCall, {'op': 'testGateway', 'school_id': 1, 'channel': 'whatsapp', 'to': '+91 9000000000'});
    });

    test('a refused test surfaces as the failure it was', () async {
      final fake = FakeCommunicationRepository(settings: twilioSettings);
      final container = makeContainer(fake);
      await container.read(communicationSettingsNotifierProvider(1).future);

      fake.failWith = const Failure(code: 'GATEWAY_TEST_FAILED', message: 'No Twilio sender number is set up.');

      await expectLater(
        container
            .read(communicationSettingsNotifierProvider(1).notifier)
            .sendTest(channel: MessageChannel.sms, to: '+91 9000000000'),
        throwsA(isA<Failure>().having((f) => f.code, 'code', 'GATEWAY_TEST_FAILED')),
      );
    });
  });

  group('MessagePageNotifier notices', () {
    test('sending to one person puts the copies in the log at once', () async {
      final fake = FakeCommunicationRepository(messages: [absenceSms]);
      final container = makeContainer(fake);
      await container.read(messagePageNotifierProvider.future);

      final result = await container
          .read(messagePageNotifierProvider.notifier)
          .sendNotice(
            schoolId: 1,
            kind: NoticeKind.message,
            audienceType: NoticeAudience.student,
            audienceId: 7,
            recipients: NoticeRecipients.both,
            channels: [MessageChannel.sms, MessageChannel.email],
            subject: 'PTA meeting',
            body: 'The PTA meets on Friday at 3 PM.',
          );

      expect(result.queued, isFalse);
      expect(result.messages, hasLength(2));
      expect(fake.lastCall!['op'], 'sendNotice');
      expect(fake.lastCall!['recipients'], 'both');
      expect(fake.lastCall!['channels'], ['sms', 'email']);

      final log = container.read(messagePageNotifierProvider).value!;
      expect(log.items, hasLength(3));
      expect(log.items.first.category, MessageCategory.general);
      expect(log.items.first.channel, MessageChannel.sms);
    });

    test('a group is queued, and the log is re-read anyway', () async {
      final fake = FakeCommunicationRepository();
      final container = makeContainer(fake);
      await container.read(messagePageNotifierProvider.future);

      final result = await container
          .read(messagePageNotifierProvider.notifier)
          .sendNotice(
            kind: NoticeKind.feeReminder,
            audienceType: NoticeAudience.classSection,
            audienceId: 11,
            recipients: NoticeRecipients.guardians,
            channels: [MessageChannel.sms],
            amount: '1500.00',
            dueDate: '2026-09-30',
          );

      expect(result.queued, isTrue);
      expect(result.messages, isEmpty);
      expect(fake.lastCall!['kind'], 'fee_reminder');
      expect(fake.lastCall!['amount'], '1500.00');
      expect(fake.lastCall!['due_date'], '2026-09-30');
      expect(fake.lastListCall!['op'], 'listMessages');
    });

    test('the preview counts per channel without sending anything', () async {
      final fake = FakeCommunicationRepository(noticeRecipients: 12);
      final container = makeContainer(fake);

      final preview = await container.read(
        noticePreviewProvider(
          const NoticeQuery(
            kind: NoticeKind.message,
            audienceType: NoticeAudience.parents,
            channels: [MessageChannel.sms, MessageChannel.inApp],
          ),
        ).future,
      );

      expect(preview.recipients, 12);
      expect(preview.countFor(MessageChannel.sms), 12);
      // Guardians have no inbox.
      expect(preview.countFor(MessageChannel.inApp), 0);
      expect(fake.lastListCall!['op'], 'previewNotice');
      expect(fake.lastListCall!['channels'], 'sms,in_app');
      expect(fake.lastCall, isNull);
    });
  });

  group('CommunicationScreen channels', () {
    testWidgets('the category tabs and channel filter cover the new kinds', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(messages: [absenceSms, feeEmail, noticeWhatsapp]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'General'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Emergency'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Fee'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Fee'));
      await tester.pumpAndSettle();
      expect(fake.lastListCall!['category'], 'fee');
      expect(find.text('Raj Kumar'), findsOneWidget);
      expect(find.text('Neha Mehta'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DropdownButtonFormField<MessageChannel?>, 'Any channel'));
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsWidgets);
      await tester.tap(find.text('WhatsApp').last);
      await tester.pumpAndSettle();

      expect(fake.lastListCall!['channel'], 'whatsapp');
      expect(find.text('Neha Mehta'), findsOneWidget);
      expect(find.text('Raj Kumar'), findsNothing);
    });

    testWidgets('an email copy shows the address it went to, in the log and in the details', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(messages: [feeEmail, absenceSms])));
      await tester.pumpAndSettle();

      // Only the email row carries an address; the SMS row shows the name alone.
      expect(find.text('raj.kumar@example.com'), findsOneWidget);
      expect(find.text('Raj Kumar'), findsNWidgets(2));

      await tester.ensureVisible(find.widgetWithText(TextButton, 'View').first);
      await tester.tap(find.widgetWithText(TextButton, 'View').first);
      await tester.pumpAndSettle();

      expect(find.text('Message details'), findsOneWidget);
      expect(find.text('Email'), findsWidgets);
      expect(find.text('raj.kumar@example.com'), findsNWidgets(2));
    });

    testWidgets('a message from another day shows its date as well as its time', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(messages: [readInApp])));
      await tester.pumpAndSettle();

      expect(find.text('15 Sep 2026, 9:00 AM'), findsOneWidget);
    });

    testWidgets('Send Message opens the compose dialog', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Send Message'));
      await tester.pumpAndSettle();

      expect(find.byType(SendNoticeDialog), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Student'), findsOneWidget);
    });
  });
}
