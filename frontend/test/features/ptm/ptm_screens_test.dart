import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/call_requests/call_requests.dart' show diallerProvider;
import 'package:edutrack_app/features/classes/application/class_section_picker_provider.dart';
import 'package:edutrack_app/features/ptm/data/ptm_models.dart';
import 'package:edutrack_app/features/ptm/data/ptm_repository.dart';
import 'package:edutrack_app/features/ptm/presentation/ptm_meetings_screen.dart';
import 'package:edutrack_app/features/ptm/presentation/ptm_slots_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/session_users.dart';

/// Parent-teacher meetings as the school runs them (docs/mobile-apps-review.md,
/// M12, 8.4): the office creates and cancels, a class teacher opens times and
/// sees who booked.
class FakePtmRepository implements PtmRepository {
  final List<PtmMeetingDraft> created = [];
  final List<int> cancelled = [];
  final List<({String from, String to, int minutes})> opened = [];
  final List<int> removed = [];
  Failure? failCreateWith;
  Failure? failOpenWith;
  List<PtmSlot> slotRows = [
    const PtmSlot(
      id: 1,
      startsAt: '09:00',
      endsAt: '09:10',
      teacherName: 'Neha Iyer',
      booking: PtmBooking(studentName: 'Asha Rao', parentName: 'Ravi Rao', parentMobile: '+91 98765 43210'),
    ),
    const PtmSlot(id: 2, startsAt: '09:10', endsAt: '09:20', teacherName: 'Neha Iyer'),
  ];

  static PtmMeeting meeting({bool cancelled = false}) => PtmMeeting(
    id: 7,
    schoolId: 1,
    title: 'Term 1 PTM',
    date: DateTime.now().add(const Duration(days: 3)),
    note: 'Please bring the report card.',
    cancelled: cancelled,
    bookingOpen: !cancelled,
    classes: const [PtmMeetingClass(id: 10, name: 'Grade 8 A', classTeacher: 'Neha Iyer', slots: 12, booked: 4)],
  );

  @override
  Future<PaginatedResponse<PtmMeeting>> list({required bool past, int page = 1}) async =>
      PaginatedResponse(items: past ? [] : [meeting()], currentPage: 1, lastPage: 1, total: past ? 0 : 1, perPage: 20);

  @override
  Future<PtmMeeting> get(int id) async => meeting();

  @override
  Future<PtmMeeting> create(PtmMeetingDraft draft) async {
    if (failCreateWith != null) throw failCreateWith!;
    created.add(draft);
    return meeting();
  }

  @override
  Future<PtmMeeting> update(int id, PtmMeetingDraft draft) async => meeting();

  @override
  Future<PtmMeeting> cancel(int id) async {
    cancelled.add(id);
    return meeting(cancelled: true);
  }

  @override
  Future<List<PtmSlot>> slots(int meetingId, int sectionId) async => slotRows;

  @override
  Future<List<PtmSlot>> openSlots(
    int meetingId,
    int sectionId, {
    required String startsAt,
    required String endsAt,
    required int minutes,
  }) async {
    if (failOpenWith != null) throw failOpenWith!;
    opened.add((from: startsAt, to: endsAt, minutes: minutes));
    return [...slotRows, const PtmSlot(id: 3, startsAt: '09:20', endsAt: '09:30')];
  }

  @override
  Future<void> removeSlot(int slotId) async => removed.add(slotId);
}

Future<(FakePtmRepository, List<Uri>)> pump(
  WidgetTester tester,
  Widget screen, {
  UserRole role = UserRole.schoolAdmin,
}) async {
  final fake = FakePtmRepository();
  final dialled = <Uri>[];
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptmRepositoryProvider.overrideWithValue(fake),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
        classSectionPickerProvider.overrideWith(
          (ref, arg) async => const [
            ClassSectionOption(id: 10, label: 'Grade 8 A'),
            ClassSectionOption(id: 11, label: 'Grade 8 B'),
          ],
        ),
        diallerProvider.overrideWithValue((uri) async {
          dialled.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (fake, dialled);
}

void main() {
  group('the meetings list', () {
    testWidgets('shows each class with its bookings', (tester) async {
      await pump(tester, const PtmMeetingsScreen());

      expect(find.text('Term 1 PTM'), findsOneWidget);
      expect(find.text('Grade 8 A'), findsOneWidget);
      expect(find.text('Neha Iyer · 4 of 12 booked'), findsOneWidget);
    });

    testWidgets('a teacher sees no New meeting, Change or Cancel', (tester) async {
      await pump(tester, const PtmMeetingsScreen(), role: UserRole.teacher);

      expect(find.byKey(const Key('ptm-new')), findsNothing);
      expect(find.byKey(const Key('ptm-edit-7')), findsNothing);
      expect(find.byKey(const Key('ptm-cancel-7')), findsNothing);
    });

    testWidgets('cancelling asks first, then cancels', (tester) async {
      final (fake, _) = await pump(tester, const PtmMeetingsScreen());

      await tester.tap(find.byKey(const Key('ptm-cancel-7')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel Term 1 PTM?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ptm-cancel-confirm')));
      await tester.pumpAndSettle();

      expect(fake.cancelled, [7]);
      expect(find.text('Meeting cancelled'), findsOneWidget);
    });

    testWidgets('keeping it cancels nothing', (tester) async {
      final (fake, _) = await pump(tester, const PtmMeetingsScreen());

      await tester.tap(find.byKey(const Key('ptm-cancel-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(fake.cancelled, isEmpty);
    });

    testWidgets('the past filter shows its own empty state', (tester) async {
      await pump(tester, const PtmMeetingsScreen());

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.text('No past meetings.'), findsOneWidget);
    });
  });

  group('the new meeting form', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('ptm-new')));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for a name, a date and a class before saving', (tester) async {
      final (fake, _) = await pump(tester, const PtmMeetingsScreen());
      await open(tester);

      await tester.tap(find.byKey(const Key('ptm-save')));
      await tester.pumpAndSettle();

      expect(find.text('Give the meeting a name.'), findsOneWidget);
      expect(find.text('Pick the date.'), findsOneWidget);
      expect(find.text('Choose at least one class.'), findsOneWidget);
      expect(fake.created, isEmpty);
    });

    testWidgets('creates the meeting with the chosen classes', (tester) async {
      final (fake, _) = await pump(tester, const PtmMeetingsScreen());
      await open(tester);

      await tester.enterText(find.byKey(const Key('ptm-title')), 'Term 1 PTM');
      await tester.tap(find.byKey(const Key('ptm-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ptm-all-classes')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ptm-save')));
      await tester.pumpAndSettle();

      expect(fake.created.single.title, 'Term 1 PTM');
      expect(fake.created.single.sectionIds, [10, 11]);
      expect(find.text('Meeting created'), findsOneWidget);
    });

    testWidgets("the server's refusal is shown on the form", (tester) async {
      final (fake, _) = await pump(tester, const PtmMeetingsScreen());
      fake.failCreateWith = const Failure(
        code: 'PTM_REFUSED',
        message: 'One of the classes chosen is not at this school.',
        details: {
          'errors': {
            'section_ids': ['One of the classes chosen is not at this school.'],
          },
        },
      );
      await open(tester);

      await tester.enterText(find.byKey(const Key('ptm-title')), 'Term 1 PTM');
      await tester.tap(find.byKey(const Key('ptm-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ptm-class-option-10')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ptm-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ptm-form-error')), findsOneWidget);
      expect(find.byKey(const Key('ptm-save')), findsOneWidget);
    });
  });

  group("a class's times", () {
    testWidgets('shows who booked, and calls them', (tester) async {
      final (_, dialled) = await pump(tester, const PtmSlotsScreen(meetingId: 7, sectionId: 10));

      expect(find.text('Grade 8 A · Term 1 PTM'), findsOneWidget);
      expect(find.text('1 of 2 booked'), findsOneWidget);
      expect(find.text('Asha Rao · Ravi Rao'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ptm-dial-1')));
      expect(dialled.single.toString(), 'tel:+919876543210');
    });

    testWidgets('opens times from 9 to 12 every 10 minutes by default', (tester) async {
      final (fake, _) = await pump(tester, const PtmSlotsScreen(meetingId: 7, sectionId: 10));

      await tester.ensureVisible(find.byKey(const Key('ptm-open')));
      await tester.tap(find.byKey(const Key('ptm-open')));
      await tester.pumpAndSettle();

      expect(fake.opened.single, (from: '09:00', to: '12:00', minutes: 10));
      expect(find.text('1 time opened'), findsOneWidget);
    });

    testWidgets("the server's refusal to open is shown", (tester) async {
      final (fake, _) = await pump(tester, const PtmSlotsScreen(meetingId: 7, sectionId: 10));
      fake.failOpenWith = const Failure(code: 'PTM_REFUSED', message: 'This meeting is over.');

      await tester.ensureVisible(find.byKey(const Key('ptm-open')));
      await tester.tap(find.byKey(const Key('ptm-open')));
      await tester.pumpAndSettle();

      expect(find.text('This meeting is over.'), findsOneWidget);
    });

    testWidgets('removing a booked time warns that the parent will be told', (tester) async {
      final (fake, _) = await pump(tester, const PtmSlotsScreen(meetingId: 7, sectionId: 10));

      await tester.ensureVisible(find.byKey(const Key('ptm-remove-1')));
      await tester.tap(find.byKey(const Key('ptm-remove-1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ravi Rao booked this time.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ptm-remove-confirm')));
      await tester.pumpAndSettle();

      expect(fake.removed, [1]);
      expect(find.text('Time removed'), findsOneWidget);
      expect(find.byKey(const Key('ptm-slot-1')), findsNothing);
    });
  });
}
