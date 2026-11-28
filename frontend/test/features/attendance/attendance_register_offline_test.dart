import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/connection_status.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/attendance/application/attendance_register_notifier.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_status.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_register/application/register_queue.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

/// The web register with no connection (docs/offline-web.md, O3): it opens
/// from the class list kept on the computer, a new register is saved and
/// sent when the line is back, and nothing changes while online.
const _params = AttendanceRegisterParams(classSectionId: 1, date: '2026-11-28');
const _network = Failure(code: 'NETWORK_ERROR', message: 'Could not reach the server.');

AttendanceRegister _register({bool submitted = false}) => AttendanceRegister(
  classSectionId: 1,
  attendanceDate: '2026-11-28',
  submitted: submitted,
  students: [
    AttendanceRosterEntry(
      studentId: 1,
      name: 'Arjun Kumar',
      rollNumber: '1',
      status: submitted ? AttendanceStatus.present : null,
      remarks: null,
    ),
    const AttendanceRosterEntry(studentId: 2, name: 'Aarav Mehta', rollNumber: '2', status: null, remarks: null),
  ],
);

void main() {
  late InMemoryKeyValueStore store;
  late FakeAttendanceRepository attendance;

  setUp(() {
    store = InMemoryKeyValueStore();
    attendance = FakeAttendanceRepository(register: _register());
  });

  Future<ProviderContainer> web({bool offlineWork = true}) async {
    final container = ProviderContainer(
      overrides: [
        offlineWorkProvider.overrideWithValue(offlineWork),
        keyValueStoreProvider.overrideWithValue(store),
        attendanceRepositoryProvider.overrideWithValue(attendance),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, id: 7)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    container.listen(registerQueueProvider, (_, _) {});
    container.listen(attendanceRegisterProvider(_params), (_, _) {});
    return container;
  }

  test('opened online once, the register opens offline from the kept class list', () async {
    final online = await web();
    await online.read(attendanceRegisterProvider(_params).future);

    attendance.failRegisterWith = _network;
    final offline = await web();
    final register = await offline.read(attendanceRegisterProvider(_params).future);

    expect(register.fromSavedList, isTrue);
    expect(register.students.map((s) => s.name), ['Arjun Kumar', 'Aarav Mehta']);
    expect(register.students.every((s) => s.status == null), isTrue);
  });

  test('never opened before, an offline register still says it cannot be reached', () async {
    attendance.failRegisterWith = _network;
    final container = await web();

    // A failing provider retries on its own, so its state is read, not its future.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = container.read(attendanceRegisterProvider(_params));
    expect(state.hasError, isTrue);
    expect((state.error! as Failure).code, 'NETWORK_ERROR');
  });

  test('a new register saved with no connection waits on the computer, then is sent', () async {
    final container = await web();
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();
    attendance.failSubmitWith = _network;

    final outcome = await notifier.submitOrUpdate(classLabel: 'Grade 8 A');

    expect(outcome, RegisterSendOutcome.savedOffline);
    expect(container.read(attendanceRegisterProvider(_params)).value!.waitingToSend, isTrue);
    final waiting = container.read(registerQueueProvider).waiting.single;
    expect(waiting.classSection, 'Grade 8 A');
    expect(waiting.marks, {1: AttendanceStatus.present, 2: AttendanceStatus.present});

    // The connection is back.
    attendance.failSubmitWith = null;
    await container.read(registerQueueProvider.notifier).retryNow();

    expect(container.read(registerQueueProvider).waiting, isEmpty);
    expect(attendance.lastSubmitPayload, isNotNull);
  });

  test('a remark on the register travels with it', () async {
    attendance = FakeAttendanceRepository(
      register: const AttendanceRegister(
        classSectionId: 1,
        attendanceDate: '2026-11-28',
        submitted: false,
        students: [
          AttendanceRosterEntry(studentId: 1, name: 'Arjun Kumar', rollNumber: '1', status: null, remarks: null),
          AttendanceRosterEntry(studentId: 2, name: 'Aarav Mehta', rollNumber: '2', status: null, remarks: 'Came late'),
        ],
      ),
    );
    final container = await web();
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();
    attendance.failSubmitWith = _network;

    await notifier.submitOrUpdate(classLabel: 'Grade 8 A');

    final waiting = container.read(registerQueueProvider).waiting.single;
    expect(waiting.remarks, {2: 'Came late'});
    expect(waiting.records.last['remarks'], 'Came late');
  });

  test('changing a submitted register offline is refused with a plain reason', () async {
    attendance = FakeAttendanceRepository(register: _register(submitted: true));
    final container = await web();
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();
    attendance.failUpdateWith = _network;

    await expectLater(
      notifier.submitOrUpdate(),
      throwsA(isA<Failure>().having((f) => f.message, 'message', contains('needs the connection'))),
    );
    expect(container.read(registerQueueProvider).waiting, isEmpty);
  });

  test('a refusal other than the connection is shown, never kept', () async {
    final container = await web();
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();
    attendance.failSubmitWith = const Failure(code: 'ATTENDANCE_ALREADY_SUBMITTED', message: 'Already submitted.');

    await expectLater(notifier.submitOrUpdate(), throwsA(isA<Failure>()));
    expect(container.read(registerQueueProvider).waiting, isEmpty);
  });

  test('off the web nothing changes: no list kept, the failure shown as before', () async {
    final container = await web(offlineWork: false);
    await container.read(attendanceRegisterProvider(_params).future);
    final notifier = container.read(attendanceRegisterProvider(_params).notifier);
    notifier.markAllPresent();
    attendance.failSubmitWith = _network;

    await expectLater(notifier.submitOrUpdate(), throwsA(isA<Failure>()));
    expect(store.values.keys.where((k) => k.startsWith('register.roster')), isEmpty);
  });
}
