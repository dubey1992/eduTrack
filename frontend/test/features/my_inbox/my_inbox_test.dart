import 'package:edutrack_app/core/utils/date_period.dart';
import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/teacher_frame.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/communication/data/models/message.dart';
import 'package:edutrack_app/features/my_inbox/data/my_inbox_repository.dart';
import 'package:edutrack_app/features/my_inbox/presentation/my_inbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_my_inbox_repository.dart';
import '../../support/session_users.dart';

/// Messages in the School365ai app (docs/teacher-app.md, T4): the bell and
/// its count, the inbox, and opening a message.
void main() {
  Widget app(FakeMyInboxRepository repository) {
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (context, state) => const TeacherFrame(
            place: TeacherPlace.today,
            child: Center(child: Text('Today')),
          ),
        ),
        GoRoute(path: '/inbox', builder: (context, state) => const MyInboxScreen()),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const Scaffold(body: Text('Me')),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        myInboxRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, name: 'Meera Joshi')),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.teacherLight(), routerConfig: router),
    );
  }

  Future<void> open(WidgetTester tester, FakeMyInboxRepository repository) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
  }

  Future<void> toInbox(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('teacher-inbox')));
    await tester.pumpAndSettle();
  }

  final twoUnreadOneRead = [
    inboxMessage(id: 1),
    inboxMessage(id: 2, subject: 'Leave approved', category: MessageCategory.leave),
    inboxMessage(id: 3, subject: 'Staff meeting moved', read: true),
  ];

  group('the bell', () {
    testWidgets('shows how many are unread', (tester) async {
      await open(tester, FakeMyInboxRepository(messages: [...twoUnreadOneRead]));

      expect(find.byKey(const Key('teacher-inbox')), findsOneWidget);
      expect(find.byKey(const Key('teacher-inbox-count')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('has no badge when nothing is unread', (tester) async {
      await open(tester, FakeMyInboxRepository(messages: [inboxMessage(read: true)]));

      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isFalse);
    });

    testWidgets('opens the inbox, and the count is read again on the way back', (tester) async {
      final repository = FakeMyInboxRepository(messages: [...twoUnreadOneRead]);
      await open(tester, repository);
      await toInbox(tester);

      expect(find.byType(MyInboxScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('inbox-read-all')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isFalse);
    });
  });

  group('the inbox', () {
    testWidgets('lists the messages newest first, the unread ones marked', (tester) async {
      await open(tester, FakeMyInboxRepository(messages: [...twoUnreadOneRead]));
      await toInbox(tester);

      expect(find.text('Sports day on Friday'), findsOneWidget);
      expect(find.text('Leave approved'), findsOneWidget);
      expect(find.text('Staff meeting moved'), findsOneWidget);
      expect(find.byKey(const Key('inbox-unread-dot-1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-unread-dot-3')), findsNothing);
      expect(find.text('Leave'), findsOneWidget, reason: "the message's category");
    });

    testWidgets('opening a message shows it whole and marks it read', (tester) async {
      final repository = FakeMyInboxRepository(messages: [...twoUnreadOneRead]);
      await open(tester, repository);
      await toInbox(tester);

      await tester.tap(find.byKey(const Key('inbox-message-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inbox-message-sheet')), findsOneWidget);
      expect(find.text('Sports day is on Friday 30 October. Classes end at noon.'), findsWidgets);
      expect(find.textContaining('Announcement · 10/26/2026 · 9:30 AM'), findsOneWidget);
      expect(repository.markedRead, [1]);

      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inbox-unread-dot-1')), findsNothing);
    });

    testWidgets('opening one already read does not ask the server again', (tester) async {
      final repository = FakeMyInboxRepository(messages: [...twoUnreadOneRead]);
      await open(tester, repository);
      await toInbox(tester);

      await tester.tap(find.byKey(const Key('inbox-message-3')));
      await tester.pumpAndSettle();

      expect(repository.markedRead, isEmpty);
    });

    testWidgets('Unread shows only those, and asks the server for only those', (tester) async {
      final repository = FakeMyInboxRepository(messages: [...twoUnreadOneRead]);
      await open(tester, repository);
      await toInbox(tester);

      await tester.tap(find.byKey(const Key('inbox-unread')));
      await tester.pumpAndSettle();

      expect(repository.lastUnreadOnly, isTrue);
      expect(find.text('Staff meeting moved'), findsNothing);
      expect(find.text('Sports day on Friday'), findsOneWidget);
    });

    testWidgets('Today asks for the messages that arrived today, and keeps Unread as it was', (tester) async {
      final repository = FakeMyInboxRepository(messages: [...twoUnreadOneRead]);
      await open(tester, repository);
      await toInbox(tester);
      await tester.tap(find.byKey(const Key('inbox-unread')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('period-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-day')));
      await tester.pumpAndSettle();

      final today = DatePeriod.day.rangeFrom(DateTime.now())!;
      expect(repository.lastRange, (today.from, today.to));
      expect(repository.lastUnreadOnly, isTrue);
    });

    testWidgets('Mark all read clears every dot and says how many', (tester) async {
      await open(tester, FakeMyInboxRepository(messages: [...twoUnreadOneRead]));
      await toInbox(tester);

      await tester.tap(find.byKey(const Key('inbox-read-all')));
      await tester.pumpAndSettle();

      expect(find.text('Marked 2 as read.'), findsOneWidget);
      expect(find.byKey(const Key('inbox-unread-dot-1')), findsNothing);
      expect(find.byKey(const Key('inbox-unread-dot-2')), findsNothing);
    });

    testWidgets('Mark all read is off when nothing is unread', (tester) async {
      await open(tester, FakeMyInboxRepository(messages: [inboxMessage(read: true)]));
      await toInbox(tester);

      final button = tester.widget<TextButton>(find.byKey(const Key('inbox-read-all')));
      expect(button.onPressed, isNull);
    });

    testWidgets('a message without a subject is titled by what it is', (tester) async {
      await open(tester, FakeMyInboxRepository(messages: [inboxMessage(subject: null)]));
      await toInbox(tester);

      expect(find.text('Announcement'), findsWidgets);
    });

    testWidgets('an empty inbox says where messages come from', (tester) async {
      await open(tester, FakeMyInboxRepository());
      await toInbox(tester);

      expect(find.byKey(const Key('inbox-empty')), findsOneWidget);
      expect(find.text('No messages yet.'), findsOneWidget);
    });

    testWidgets('a failure offers a retry', (tester) async {
      final repository = FakeMyInboxRepository(messages: [inboxMessage()], failListWith: Failure.network());
      await open(tester, repository);
      await toInbox(tester);

      expect(find.text('Retry'), findsOneWidget);

      repository.failListWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Sports day on Friday'), findsOneWidget);
    });
  });
}
