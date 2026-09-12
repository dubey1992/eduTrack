import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/communication/data/communication_repository.dart';
import 'package:edutrack_app/features/communication/presentation/communication_screen.dart';
import 'package:edutrack_app/features/communication/presentation/inbox_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/communication_fixtures.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_communication_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);
const _teacher = AuthenticatedUser(id: 20, name: 'Priya Sharma', email: 'priya@example.com', role: UserRole.teacher);

Widget wrap(FakeCommunicationRepository fake, {AuthenticatedUser actor = _admin, Widget? home}) {
  return ProviderScope(
    overrides: [
      communicationRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: home ?? const CommunicationScreen()),
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
  testWidgets('the log shows the KPI tiles and the prototype columns', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository(messages: [absenceSms, boardingSms, failedSms]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('SMS Sent Today'), findsOneWidget);
    expect(find.text('Delivery Rate'), findsOneWidget);
    expect(find.text('Failed'), findsWidgets);
    expect(find.text('66.7%'), findsOneWidget);

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('Raj Kumar'), findsOneWidget);
    expect(find.text('Arjun Kumar'), findsOneWidget);
    expect(find.text('Delivered'), findsNWidgets(2));
  });

  testWidgets('an empty log explains itself instead of showing a blank table', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeCommunicationRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No messages have been sent yet.'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
  });

  testWidgets('a log filtered down to nothing says so differently', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository(messages: [absenceSms]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Transport'));
    await tester.pumpAndSettle();

    expect(find.text('No messages match these filters.'), findsOneWidget);
    expect(find.text('No messages have been sent yet.'), findsNothing);
  });

  testWidgets('a load failure offers a retry rather than a blank screen', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository()
      ..failWith = const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.');
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsWidgets);
  });

  testWidgets('the category tabs filter the log', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository(messages: [absenceSms, boardingSms]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Raj Kumar'), findsOneWidget);
    expect(find.text('Neha Mehta'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Transport'));
    await tester.pumpAndSettle();

    expect(fake.lastListCall!['category'], 'transport');
    expect(find.text('Raj Kumar'), findsNothing);
    expect(find.text('Neha Mehta'), findsOneWidget);
  });

  testWidgets('searching passes the term to the server', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository(messages: [absenceSms, boardingSms]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Search recipient, student or text'), 'Aarav');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(fake.lastListCall!['q'], 'Aarav');
    expect(find.text('Neha Mehta'), findsOneWidget);
    expect(find.text('Raj Kumar'), findsNothing);
  });

  testWidgets('a failed message can be sent again and reports success', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository(messages: [failedSms]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsWidgets);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Send again'));
    await tester.tap(find.widgetWithText(FilledButton, 'Send again'));
    await tester.pumpAndSettle();

    expect(fake.lastCall, {'op': 'retry', 'message_id': failedSms.id});
    expect(find.text('Message queued to send again.'), findsOneWidget);
    expect(find.text('Queued'), findsWidgets);
  });

  testWidgets('a delivered message offers no resend', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeCommunicationRepository(messages: [absenceSms])));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Send again'), findsNothing);
    expect(find.widgetWithText(TextButton, 'View'), findsOneWidget);
  });

  testWidgets('the detail dialog explains why a message was not sent', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeCommunicationRepository(messages: [skippedSms])));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(TextButton, 'View'));
    await tester.tap(find.widgetWithText(TextButton, 'View'));
    await tester.pumpAndSettle();

    expect(find.text('Message details'), findsOneWidget);
    expect(find.text('Why it was not sent'), findsOneWidget);
    expect(find.text('No mobile number on record.'), findsOneWidget);
    expect(find.text('Kiran Rao was marked ABSENT on 16 Sep 2026.'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('Message details'), findsNothing);
  });

  testWidgets('the retry failure is surfaced and the row stays failed', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository(messages: [failedSms]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    fake.failWith = const Failure(code: 'MESSAGE_NOT_RETRYABLE', message: 'Only a failed message can be sent again.');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Send again'));
    await tester.tap(find.widgetWithText(FilledButton, 'Send again'));
    await tester.pumpAndSettle();

    expect(find.text('Only a failed message can be sent again.'), findsOneWidget);
  });

  testWidgets('the mobile layout uses cards and no data table', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(FakeCommunicationRepository(messages: [absenceSms])));
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Raj Kumar'), findsOneWidget);
  });

  group('Inbox', () {
    testWidgets('lists in-app messages with an unread count', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(messages: [leaveInApp, readInApp, absenceSms]);
      await tester.pumpWidget(wrap(fake, actor: _teacher, home: const InboxScreen()));
      await tester.pumpAndSettle();

      expect(find.text('1 unread message.'), findsOneWidget);
      expect(find.text('Leave approved'), findsOneWidget);
      expect(find.text('Leave rejected'), findsOneWidget);
      // The SMS copy of a leave decision belongs in the log, not the inbox.
      expect(find.text('Marked absent'), findsNothing);
    });

    testWidgets('marking one read clears its action and updates the count', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(messages: [leaveInApp, readInApp]);
      await tester.pumpWidget(wrap(fake, actor: _teacher, home: const InboxScreen()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Mark read'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Mark read'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {'op': 'markRead', 'message_id': leaveInApp.id});
      expect(find.widgetWithText(TextButton, 'Mark read'), findsNothing);
      expect(find.text('Nothing unread.'), findsOneWidget);
    });

    testWidgets('mark all read reports how many it cleared', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(messages: [leaveInApp, readInApp]);
      await tester.pumpWidget(wrap(fake, actor: _teacher, home: const InboxScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Mark all read'));
      await tester.pumpAndSettle();

      expect(find.text('1 message marked read.'), findsOneWidget);
    });

    testWidgets('an empty inbox says so and disables mark all read', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), actor: _teacher, home: const InboxScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No messages yet.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Mark all read')).onPressed, isNull);
    });

    testWidgets('the unread filter narrows the list', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository(messages: [leaveInApp, readInApp]);
      await tester.pumpWidget(wrap(fake, actor: _teacher, home: const InboxScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Unread only'));
      await tester.pumpAndSettle();

      expect(fake.lastListCall!['unread'], isTrue);
      expect(find.text('Leave rejected'), findsNothing);
      expect(find.text('Leave approved'), findsOneWidget);
    });
  });
}
