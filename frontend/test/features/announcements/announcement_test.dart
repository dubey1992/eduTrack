import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/announcements/application/announcement_page_notifier.dart';
import 'package:edutrack_app/features/announcements/data/announcement_repository.dart';
import 'package:edutrack_app/features/announcements/data/models/announcement.dart';
import 'package:edutrack_app/features/announcements/presentation/announcement_screen.dart';
import 'package:edutrack_app/features/announcements/presentation/new_announcement_dialog.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/announcement_fixtures.dart';
import '../../support/fake_announcement_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_school_repository.dart';

/// One class with one section, so the compose form's class picker has
/// something real to choose.
final _grade8 = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(id: 1, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
  ],
);

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

/// The compose dialog is opened through a real showDialog route (behind an
/// "Open" button), so popping it on success still leaves a page behind to
/// show the confirmation on.
Future<void> openDialog(WidgetTester tester, FakeAnnouncementRepository fake) async {
  await tester.pumpWidget(
    wrap(
      fake,
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => const NewAnnouncementDialog(schoolId: null)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Open'));
  await tester.pumpAndSettle();
}

Widget wrap(FakeAnnouncementRepository fake, {Widget? home, AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    overrides: [
      announcementRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
      schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_grade8])),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: home ?? const AnnouncementScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('AnnouncementPageNotifier', () {
    ProviderContainer makeContainer(FakeAnnouncementRepository fake) {
      final container = ProviderContainer(
        overrides: [announcementRepositoryProvider.overrideWithValue(fake)],
        retry: (retryCount, error) => null,
      );
      addTearDown(container.dispose);
      return container;
    }

    test('lists what has been published', () async {
      final container = makeContainer(FakeAnnouncementRepository(announcements: [parentMeeting, syllabusReview]));

      final page = await container.read(announcementPageNotifierProvider.future);

      expect(page.items, hasLength(2));
      expect(page.items.first.title, 'Parent meeting');
    });

    test('filters by audience, search term and whether it is still showing', () async {
      final fake = FakeAnnouncementRepository(announcements: [parentMeeting, syllabusReview, oldSportsDay]);
      final container = makeContainer(fake);
      await container.read(announcementPageNotifierProvider.future);
      final notifier = container.read(announcementPageNotifierProvider.notifier);

      await notifier.setFilters(audienceType: AnnouncementAudience.department);
      expect(container.read(announcementPageNotifierProvider).value!.items.single.title, 'Syllabus review');
      expect(fake.lastListCall!['audience_type'], 'department');

      await notifier.setFilters(search: 'Sports');
      expect(container.read(announcementPageNotifierProvider).value!.items.single.title, 'Sports day');

      await notifier.setFilters(activeOnly: true);
      expect(container.read(announcementPageNotifierProvider).value!.items, hasLength(2));
    });

    test('publishing adds it to the list and reports who it reached', () async {
      final fake = FakeAnnouncementRepository(previewRecipients: 12);
      final container = makeContainer(fake);
      await container.read(announcementPageNotifierProvider.future);

      final published = await container
          .read(announcementPageNotifierProvider.notifier)
          .publish(
            title: 'Sports day moved',
            body: 'The sports day is now on Friday.',
            audienceType: AnnouncementAudience.allSchool,
            channels: AnnouncementChannels.smsAndInApp,
            expiresAt: '2026-09-30',
          );

      expect(published.recipientsCount, 12);
      expect(fake.lastCall, {
        'op': 'publish',
        'school_id': null,
        'title': 'Sports day moved',
        'body': 'The sports day is now on Friday.',
        'audience_type': 'all_school',
        'audience_id': null,
        'channels': 'sms_in_app',
        'expires_at': '2026-09-30',
      });
      expect(container.read(announcementPageNotifierProvider).value!.items.first.title, 'Sports day moved');
    });

    test('deleting takes it off the list', () async {
      final fake = FakeAnnouncementRepository(announcements: [parentMeeting]);
      final container = makeContainer(fake);
      await container.read(announcementPageNotifierProvider.future);

      await container.read(announcementPageNotifierProvider.notifier).delete(parentMeeting);

      expect(fake.lastCall, {'op': 'delete', 'announcement_id': parentMeeting.id});
      expect(container.read(announcementPageNotifierProvider).value!.items, isEmpty);
    });

    test('the audience preview reports nobody for an in-app notice to guardians', () async {
      final container = makeContainer(FakeAnnouncementRepository(previewRecipients: 40));

      final reachable = await container.read(
        audiencePreviewProvider(
          const AudienceQuery(audienceType: AnnouncementAudience.allSchool, channels: AnnouncementChannels.inAppOnly),
        ).future,
      );
      expect(reachable.recipients, 40);

      final unreachable = await container.read(
        audiencePreviewProvider(
          const AudienceQuery(audienceType: AnnouncementAudience.parents, channels: AnnouncementChannels.inAppOnly),
        ).future,
      );
      expect(unreachable.recipients, 0);
    });
  });

  group('AnnouncementScreen', () {
    testWidgets('lists notices with their audience, channel and reach', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeAnnouncementRepository(announcements: [parentMeeting, oldSportsDay])));
      await tester.pumpAndSettle();

      expect(find.text('Parent meeting'), findsOneWidget);
      expect(find.text('Parents'), findsWidgets);
      expect(find.text('SMS + In-app'), findsOneWidget);
      expect(find.textContaining('reached 42 people'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('an empty list says so', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeAnnouncementRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Nothing has been announced yet.'), findsOneWidget);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository()
        ..failWith = const Failure(code: 'SERVER_ERROR', message: 'Announcements could not be loaded.');
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.text('Announcements could not be loaded.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    });

    testWidgets('deleting asks first and explains what stays in the log', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository(announcements: [parentMeeting]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete announcement?'), findsOneWidget);
      expect(find.textContaining('cannot be unsent'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();
      expect(fake.lastCall, isNull);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {'op': 'delete', 'announcement_id': parentMeeting.id});
      expect(find.text('"Parent meeting" deleted.'), findsOneWidget);
      expect(find.text('Nothing has been announced yet.'), findsOneWidget);
    });

    testWidgets('the audience filter narrows the list', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository(announcements: [parentMeeting, syllabusReview]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<AnnouncementAudience?>, 'Any audience'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A department').last);
      await tester.pumpAndSettle();

      expect(fake.lastListCall!['audience_type'], 'department');
      expect(find.text('Parent meeting'), findsNothing);
      expect(find.text('Syllabus review'), findsOneWidget);
    });
  });

  group('NewAnnouncementDialog as a head of department', () {
    const hod = AuthenticatedUser(id: 9, name: 'Vikram Rao', email: 'vikram@example.com', role: UserRole.hod);

    testWidgets('is offered only the department audience, already selected', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          FakeAnnouncementRepository(),
          actor: hod,
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showDialog<void>(context: context, builder: (_) => const NewAnnouncementDialog(schoolId: null)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Open'));
      await tester.pumpAndSettle();

      // The audience is pinned to the one thing they may do.
      expect(find.text('A department'), findsOneWidget);
      await tester.tap(find.widgetWithText(DropdownButtonFormField<AnnouncementAudience>, 'A department'));
      await tester.pumpAndSettle();
      expect(find.text('All School'), findsNothing);
      expect(find.text('Parents'), findsNothing);
    });
  });

  group('NewAnnouncementDialog', () {
    testWidgets('publishes to the chosen audience and channel', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository(previewRecipients: 42);
      await openDialog(tester, fake);
      await tester.pumpAndSettle();

      expect(find.text('New Announcement'), findsOneWidget);
      expect(find.textContaining('Goes to 42 people'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Announcement title'), 'Parent meeting');
      await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Parent meeting scheduled Friday at 3 PM.');
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['title'], 'Parent meeting');
      expect(fake.lastCall!['audience_type'], 'all_school');
      expect(fake.lastCall!['channels'], 'sms_in_app');
      expect(fake.lastCall!['expires_at'], isNull);
      expect(find.text('Announcement published to 42 people.'), findsOneWidget);
    });

    testWidgets('an empty title or message is refused before it reaches the server', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a title.'), findsOneWidget);
      expect(find.text('Enter the message to send.'), findsOneWidget);
      expect(fake.lastCall, isNull);

      await tester.enterText(find.widgetWithText(TextFormField, 'Announcement title'), 'Hi');
      await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Too short');
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.text('That title is too short.'), findsOneWidget);
      expect(find.text('That message is too short.'), findsOneWidget);
      expect(fake.lastCall, isNull);
    });

    testWidgets('a class audience reveals a class picker and sends its id', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<AnnouncementAudience>, 'All School'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A class section').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(DropdownButtonFormField<int>, 'Class'), findsOneWidget);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grade 8 A').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Announcement title'), 'Class outing');
      await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'The outing is on Tuesday.');
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['audience_type'], 'class_section');
      expect(fake.lastCall!['audience_id'], isNotNull);
    });

    testWidgets('an in-app notice to guardians warns that it reaches nobody', (tester) async {
      useDesktop(tester);
      await openDialog(tester, FakeAnnouncementRepository());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<AnnouncementAudience>, 'All School'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parents').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<AnnouncementChannels>, 'SMS + In-app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('In-app Only').last);
      await tester.pumpAndSettle();

      expect(find.text('Guardians have no app login, so this audience can only be reached by SMS.'), findsOneWidget);
      expect(find.text('Nobody in this audience can be reached on that channel.'), findsOneWidget);
    });

    testWidgets('a rejection clears when the audience is changed', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake);

      await tester.enterText(find.widgetWithText(TextFormField, 'Announcement title'), 'Parent meeting');
      await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Parent meeting on Friday at 3 PM.');

      fake.failWith = const Failure(code: 'UNREACHABLE_AUDIENCE', message: 'Nobody can be reached.');
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();
      expect(find.text('Nobody can be reached.'), findsOneWidget);

      fake.failWith = null;
      await tester.tap(find.widgetWithText(DropdownButtonFormField<AnnouncementAudience>, 'All School'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teachers').last);
      await tester.pumpAndSettle();

      expect(find.text('Nobody can be reached.'), findsNothing);
    });

    testWidgets('a server rejection is shown in the dialog and it stays open', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Announcement title'), 'Parent meeting');
      await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Parent meeting on Friday at 3 PM.');

      fake.failWith = const Failure(
        code: 'UNREACHABLE_AUDIENCE',
        message: 'Guardians have no app login, so this audience can only be reached by SMS.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.text('New Announcement'), findsOneWidget);
      expect(find.text('Guardians have no app login, so this audience can only be reached by SMS.'), findsOneWidget);
    });
  });
}
