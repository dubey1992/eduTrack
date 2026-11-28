import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/connection_status.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/announcements/data/announcement_repository.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_teaching/application/staff_outbox.dart';
import 'package:edutrack_app/features/my_teaching/data/outbox.dart';
import 'package:edutrack_app/features/staff_attendance/data/models/staff_attendance_register.dart';
import 'package:edutrack_app/features/staff_attendance/data/staff_attendance_repository.dart';
import 'package:edutrack_app/features/staff_leave/data/staff_leave_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_announcement_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_staff_attendance_repository.dart';
import '../../support/fake_staff_leave_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

/// The web office's work saved with no connection and sent when the line is
/// back (docs/offline-web.md, O3): a staff register, a leave application and
/// a notice. The outbox runs on timers, so these are widget tests.
void main() {
  late InMemoryKeyValueStore store;
  late FakeStaffAttendanceRepository staffAttendance;
  late FakeStaffLeaveRepository leave;
  late FakeAnnouncementRepository notices;

  setUp(() {
    store = InMemoryKeyValueStore();
    staffAttendance = FakeStaffAttendanceRepository(
      register: const StaffAttendanceRegister(schoolId: 1, attendanceDate: '2026-11-28', submitted: false, staff: []),
    );
    leave = FakeStaffLeaveRepository();
    notices = FakeAnnouncementRepository();
  });

  Future<ProviderContainer> office({bool offlineWork = true}) async {
    final container = ProviderContainer(
      overrides: [
        offlineWorkProvider.overrideWithValue(offlineWork),
        keyValueStoreProvider.overrideWithValue(store),
        staffAttendanceRepositoryProvider.overrideWithValue(staffAttendance),
        staffLeaveRepositoryProvider.overrideWithValue(leave),
        announcementRepositoryProvider.overrideWithValue(notices),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.schoolAdmin, id: 3)),
        ),
      ],
    );
    await container.read(authNotifierProvider.future);
    container.listen(staffOutboxProvider, (_, _) {});
    return container;
  }

  Future<bool> keep(ProviderContainer container, OutboxKind kind, Map<String, dynamic> payload) => container
      .read(staffOutboxProvider.notifier)
      .keepFromWeb(kind: kind, key: OutboxItem.uniqueKey(kind.apiValue), label: 'Saved offline', payload: payload);

  testWidgets('a staff register waits with no connection, then is sent', (tester) async {
    staffAttendance.failSubmitWith = Failure.network();
    final container = await office();

    expect(
      await keep(container, OutboxKind.staffRegister, {
        'school_id': null,
        'department_id': null,
        'attendance_date': '2026-11-28',
        'records': [
          {'staff_profile_id': 1, 'status': 'present'},
        ],
        'confirm_leave': false,
      }),
      isTrue,
    );
    await tester.pump();
    expect(container.read(staffOutboxProvider), hasLength(1));

    staffAttendance.failSubmitWith = null;
    await tester.pump(StaffOutbox.retryDelays.first);

    expect(container.read(staffOutboxProvider), isEmpty);
    expect(staffAttendance.lastSubmitPayload?['attendance_date'], '2026-11-28');
    container.dispose();
  });

  testWidgets('a leave application is sent as it was filled in', (tester) async {
    final container = await office();

    await keep(container, OutboxKind.leave, {
      'leave_type': 'casual',
      'start_date': '2026-12-01',
      'end_date': '2026-12-02',
      'reason': 'Family function',
    });
    await tester.pump();

    expect(leave.lastApplyPayload, {
      'leave_type': 'casual',
      'start_date': '2026-12-01',
      'end_date': '2026-12-02',
      'reason': 'Family function',
    });
    expect(container.read(staffOutboxProvider), isEmpty);
    container.dispose();
  });

  testWidgets('a notice goes out with its files when the line is back', (tester) async {
    final container = await office();

    await keep(container, OutboxKind.notice, {
      'school_id': null,
      'title': 'Sports day',
      'body': 'Friday on the field.',
      'audience_type': 'all_school',
      'audience_id': null,
      'channels': 'in_app',
      'expires_at': null,
      'reply_question': null,
      'reply_by': null,
      'attachment_ids': [41],
    });
    await tester.pump();

    expect(notices.lastCall?['title'], 'Sports day');
    expect(notices.lastCall?['attachment_ids'], [41]);
    container.dispose();
  });

  testWidgets('what the server turns down is kept with its reason, not resent', (tester) async {
    leave.failApplyWith = const Failure(code: 'LEAVE_OVERLAPS', message: 'You already have leave on these days.');
    final container = await office();

    await keep(container, OutboxKind.leave, {
      'leave_type': 'casual',
      'start_date': '2026-12-01',
      'end_date': '2026-12-01',
      'reason': 'Errand',
    });
    await tester.pump();

    final item = container.read(staffOutboxProvider).single;
    expect(item.refusal, 'You already have leave on these days.');
    container.dispose();
  });

  testWidgets('off the web nothing is kept - the form shows its error as before', (tester) async {
    final container = await office(offlineWork: false);

    expect(await keep(container, OutboxKind.leave, {'leave_type': 'casual'}), isFalse);
    expect(container.read(staffOutboxProvider), isEmpty);
    container.dispose();
  });
}
