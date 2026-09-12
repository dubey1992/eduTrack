import 'package:edutrack_app/features/communication/application/inbox_notifier.dart';
import 'package:edutrack_app/features/communication/application/message_page_notifier.dart';
import 'package:edutrack_app/features/communication/application/template_notifier.dart';
import 'package:edutrack_app/features/communication/data/communication_repository.dart';
import 'package:edutrack_app/features/communication/data/models/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/communication_fixtures.dart';
import '../../support/fake_communication_repository.dart';

void main() {
  ProviderContainer makeContainer(FakeCommunicationRepository fake) {
    final container = ProviderContainer(
      overrides: [communicationRepositoryProvider.overrideWithValue(fake)],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  group('MessagePageNotifier', () {
    test('loads the log and reports the page meta', () async {
      final fake = FakeCommunicationRepository(messages: [absenceSms, boardingSms, failedSms]);
      final container = makeContainer(fake);

      final page = await container.read(messagePageNotifierProvider.future);

      expect(page.items, hasLength(3));
      expect(page.total, 3);
      expect(page.currentPage, 1);
    });

    test('the category tabs filter the log server-side', () async {
      final fake = FakeCommunicationRepository(messages: [absenceSms, boardingSms, leaveInApp]);
      final container = makeContainer(fake);
      await container.read(messagePageNotifierProvider.future);

      await container.read(messagePageNotifierProvider.notifier).setCategory(MessageCategory.transport);

      expect(container.read(messagePageNotifierProvider).value!.items.single.id, boardingSms.id);
      expect(fake.lastListCall!['category'], 'transport');
      expect(container.read(messagePageNotifierProvider.notifier).category, MessageCategory.transport);
    });

    test('status, channel and search filters are passed through together', () async {
      final fake = FakeCommunicationRepository(messages: [absenceSms, boardingSms, failedSms]);
      final container = makeContainer(fake);
      await container.read(messagePageNotifierProvider.future);

      await container
          .read(messagePageNotifierProvider.notifier)
          .setFilters(status: MessageStatus.failed, channel: MessageChannel.sms, search: '  Meera  ');

      expect(fake.lastListCall!['status'], 'failed');
      expect(fake.lastListCall!['channel'], 'sms');
      expect(fake.lastListCall!['q'], 'Meera');
      expect(container.read(messagePageNotifierProvider).value!.items.single.id, failedSms.id);
    });

    test('an empty search term is dropped rather than sent as a blank filter', () async {
      final fake = FakeCommunicationRepository(messages: [absenceSms]);
      final container = makeContainer(fake);
      await container.read(messagePageNotifierProvider.future);

      await container.read(messagePageNotifierProvider.notifier).setFilters(search: '   ');

      expect(fake.lastListCall!['q'], isNull);
    });

    test('retrying a failed message queues it and refreshes the list', () async {
      final fake = FakeCommunicationRepository(messages: [failedSms]);
      final container = makeContainer(fake);
      await container.read(messagePageNotifierProvider.future);

      await container.read(messagePageNotifierProvider.notifier).retry(failedSms);

      expect(fake.lastCall, {'op': 'retry', 'message_id': failedSms.id});
      expect(container.read(messagePageNotifierProvider).value!.items.single.status, MessageStatus.queued);
    });

    test('the summary reports the delivery rate, and null when nothing was attempted', () async {
      final withTraffic = makeContainer(FakeCommunicationRepository(messages: [absenceSms, boardingSms, failedSms]));
      final summary = await withTraffic.read(messageSummaryProvider(null).future);
      expect(summary.sentToday, 2);
      expect(summary.failedToday, 1);
      expect(summary.deliveryRate, closeTo(66.7, 0.1));

      final quiet = makeContainer(FakeCommunicationRepository(messages: [skippedSms]));
      final none = await quiet.read(messageSummaryProvider(null).future);
      expect(none.deliveryRate, isNull);
      expect(none.skippedToday, 1);
    });
  });

  group('TemplateNotifier', () {
    test('rewording an event marks it custom', () async {
      final fake = FakeCommunicationRepository();
      final container = makeContainer(fake);
      await container.read(templateNotifierProvider(1).future);

      await container
          .read(templateNotifierProvider(1).notifier)
          .save('attendance.absent', 'New wording {student_name}.');

      expect(fake.lastCall, {
        'op': 'updateTemplate',
        'event': 'attendance.absent',
        'school_id': 1,
        'body': 'New wording {student_name}.',
      });

      final templates = container.read(templateNotifierProvider(1)).value!;
      expect(templates.firstWhere((t) => t.event == 'attendance.absent').isCustom, isTrue);
    });

    test('resetting puts the shipped wording back', () async {
      final fake = FakeCommunicationRepository();
      final container = makeContainer(fake);
      await container.read(templateNotifierProvider(1).future);

      await container.read(templateNotifierProvider(1).notifier).resetToDefault('transport.boarded');

      final boarded = container
          .read(templateNotifierProvider(1))
          .value!
          .firstWhere((t) => t.event == 'transport.boarded');
      expect(boarded.isCustom, isFalse);
      expect(boarded.body, boardedTemplate.defaultBody);
    });
  });

  group('CommunicationSettingsNotifier', () {
    test('loads the school defaults and saves a change', () async {
      final fake = FakeCommunicationRepository();
      final container = makeContainer(fake);

      final loaded = await container.read(communicationSettingsNotifierProvider(1).future);
      expect(loaded.isSaved, isFalse);
      expect(loaded.attendanceAlerts, AttendanceAlertMode.absentOnly);

      await container
          .read(communicationSettingsNotifierProvider(1).notifier)
          .save(
            smsEnabled: true,
            attendanceAlerts: AttendanceAlertMode.presentAndAbsent,
            transportAlertsEnabled: false,
            leaveAlertsEnabled: true,
            provider: 'log',
            senderId: 'SUNRIS',
          );

      expect(fake.lastCall!['attendance_alerts'], 'both');
      expect(fake.lastCall!['transport_alerts_enabled'], false);
      expect(fake.lastCall!['sender_id'], 'SUNRIS');

      final saved = container.read(communicationSettingsNotifierProvider(1)).value!;
      expect(saved.isSaved, isTrue);
      expect(saved.attendanceAlerts, AttendanceAlertMode.presentAndAbsent);
    });
  });

  group('InboxNotifier', () {
    test('lists only in-app messages and counts the unread ones', () async {
      final fake = FakeCommunicationRepository(messages: [absenceSms, leaveInApp, readInApp]);
      final container = makeContainer(fake);

      final page = await container.read(inboxNotifierProvider.future);

      expect(page.items.map((m) => m.id), [leaveInApp.id, readInApp.id]);
      expect(await container.read(unreadCountProvider.future), 1);
    });

    test('the unread filter narrows the list', () async {
      final fake = FakeCommunicationRepository(messages: [leaveInApp, readInApp]);
      final container = makeContainer(fake);
      await container.read(inboxNotifierProvider.future);

      await container.read(inboxNotifierProvider.notifier).setUnreadOnly(true);

      expect(container.read(inboxNotifierProvider).value!.items.single.id, leaveInApp.id);
      expect(fake.lastListCall!['unread'], isTrue);
    });

    test('marking one read updates it, and an already-read message is left alone', () async {
      final fake = FakeCommunicationRepository(messages: [leaveInApp, readInApp]);
      final container = makeContainer(fake);
      await container.read(inboxNotifierProvider.future);

      await container.read(inboxNotifierProvider.notifier).markRead(leaveInApp);
      expect(fake.lastCall, {'op': 'markRead', 'message_id': leaveInApp.id});
      expect(fake.messages.firstWhere((m) => m.id == leaveInApp.id).isUnread, isFalse);

      fake.lastCall = null;
      await container.read(inboxNotifierProvider.notifier).markRead(readInApp);
      expect(fake.lastCall, isNull);
    });

    test('mark all read reports how many it cleared', () async {
      final fake = FakeCommunicationRepository(messages: [leaveInApp, readInApp]);
      final container = makeContainer(fake);
      await container.read(inboxNotifierProvider.future);

      expect(await container.read(inboxNotifierProvider.notifier).markAllRead(), 1);
      expect(await container.read(unreadCountProvider.future), 0);
    });
  });
}
