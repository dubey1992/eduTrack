import 'dart:convert';

import 'package:edutrack_app/features/attendance/data/models/attendance_status.dart';
import 'package:edutrack_app/features/my_register/application/register_queue.dart';
import 'package:edutrack_app/features/my_register/data/models/saved_register.dart';
import 'package:edutrack_app/features/my_register/data/register_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import 'register_fixtures.dart';

/// The register queue (docs/teacher-app.md, T2). It runs on timers - its
/// back-off - so these are widget tests: `tester.pump(duration)` moves the
/// clock.
void main() {
  late FakeAttendanceRepository attendance;
  late InMemoryKeyValueStore store;

  setUp(() {
    attendance = FakeAttendanceRepository(register: registerOf());
    store = InMemoryKeyValueStore();
  });

  List<dynamic> stored(String key) => jsonDecode(store.values[key] ?? '[]') as List<dynamic>;

  testWidgets('with signal, a register is sent at once and nothing is left on the phone', (tester) async {
    final phone = await signedInPhone(attendance, store);

    await phone.read(registerQueueProvider.notifier).submit(savedRegister());

    expect(attendance.submitCallCount, 1);
    expect(attendance.lastSubmitPayload!['class_section_id'], sectionId);
    expect(attendance.lastSubmitPayload!['attendance_date'], day);
    expect(attendance.lastSubmitPayload!['records'], [
      {'student_id': 1, 'status': 'present'},
      {'student_id': 2, 'status': 'absent'},
      {'student_id': 3, 'status': 'present'},
    ]);
    final state = phone.read(registerQueueProvider);
    expect(state.waiting, isEmpty);
    expect(state.unsent, isEmpty);
    expect(state.offline, isFalse);
    expect(stored('register.waiting'), isEmpty);

    phone.dispose();
  });

  testWidgets('without signal, the register is kept on the phone and the queue says it is offline', (tester) async {
    attendance.failSubmitWith = noSignal;
    final phone = await signedInPhone(attendance, store);

    await phone.read(registerQueueProvider.notifier).submit(savedRegister());

    final state = phone.read(registerQueueProvider);
    expect(state.waitingFor(sectionId, day), isNotNull);
    expect(state.offline, isTrue);
    expect(state.sending, isFalse);
    expect(stored('register.waiting'), hasLength(1));

    phone.dispose();
  });

  testWidgets('tries again after 5, then 15 seconds, and sends once signal is back', (tester) async {
    attendance.failSubmitWith = noSignal;
    final phone = await signedInPhone(attendance, store);
    await phone.read(registerQueueProvider.notifier).submit(savedRegister());
    expect(attendance.submitCallCount, 1);

    await tester.pump(const Duration(seconds: 4));
    expect(attendance.submitCallCount, 1, reason: 'not before the first back-off is up');
    await tester.pump(const Duration(seconds: 1));
    expect(attendance.submitCallCount, 2);

    attendance.failSubmitWith = null;
    await tester.pump(const Duration(seconds: 15));
    expect(attendance.submitCallCount, 3);
    expect(phone.read(registerQueueProvider).waiting, isEmpty);
    expect(phone.read(registerQueueProvider).offline, isFalse);

    // Sent: no more tries.
    await tester.pump(const Duration(minutes: 2));
    expect(attendance.submitCallCount, 3);

    phone.dispose();
  });

  testWidgets('retryNow sends at once rather than waiting out the back-off', (tester) async {
    attendance.failSubmitWith = noSignal;
    final phone = await signedInPhone(attendance, store);
    await phone.read(registerQueueProvider.notifier).submit(savedRegister());

    attendance.failSubmitWith = null;
    await phone.read(registerQueueProvider.notifier).retryNow();

    expect(attendance.submitCallCount, 2);
    expect(phone.read(registerQueueProvider).waiting, isEmpty);

    phone.dispose();
  });

  testWidgets('a register the server refuses moves to "not sent" with its reason, and is not retried', (tester) async {
    attendance.failSubmitWith = alreadyTaken;
    final phone = await signedInPhone(attendance, store);

    await phone.read(registerQueueProvider.notifier).submit(savedRegister());

    final state = phone.read(registerQueueProvider);
    expect(state.waiting, isEmpty);
    expect(state.unsentFor(sectionId, day)!.reason, 'Attendance has already been submitted.');
    expect(stored('register.unsent'), hasLength(1));

    await tester.pump(const Duration(minutes: 2));
    expect(attendance.submitCallCount, 1);

    phone.dispose();
  });

  testWidgets('taking the register again replaces the waiting one and clears the old refusal', (tester) async {
    attendance.failSubmitWith = alreadyTaken;
    final phone = await signedInPhone(attendance, store);
    final queue = phone.read(registerQueueProvider.notifier);
    await queue.submit(savedRegister(clientId: 'first'));
    expect(phone.read(registerQueueProvider).unsent, hasLength(1));

    attendance.failSubmitWith = noSignal;
    await queue.submit(savedRegister(clientId: 'second', marks: const {1: AttendanceStatus.present}));
    await queue.submit(savedRegister(clientId: 'third'));

    final state = phone.read(registerQueueProvider);
    expect(state.unsent, isEmpty);
    expect(state.waiting.map((r) => r.clientId), ['third'], reason: 'one register per class and day');

    phone.dispose();
  });

  testWidgets('a register left waiting when the app closed is sent when it opens again', (tester) async {
    await RegisterStore(store).saveWaiting([savedRegister()]);
    final phone = await signedInPhone(attendance, store);

    phone.read(registerQueueProvider);
    await tester.pump();
    await tester.pump();

    expect(attendance.submitCallCount, 1);
    expect(phone.read(registerQueueProvider).waiting, isEmpty);
    expect(stored('register.waiting'), isEmpty);

    phone.dispose();
  });

  testWidgets("another teacher's register on a shared phone is never sent under this sign-in", (tester) async {
    await RegisterStore(store).saveWaiting([savedRegister(userId: 99)]);
    final phone = await signedInPhone(attendance, store);

    phone.read(registerQueueProvider);
    await tester.pump();
    await phone.read(registerQueueProvider.notifier).retryNow();

    expect(attendance.submitCallCount, 0);
    expect(phone.read(registerQueueProvider).waiting, hasLength(1), reason: 'kept for its own teacher');

    phone.dispose();
  });

  testWidgets('dismissing a refusal puts it away for good', (tester) async {
    attendance.failSubmitWith = alreadyTaken;
    final phone = await signedInPhone(attendance, store);
    final queue = phone.read(registerQueueProvider.notifier);
    await queue.submit(savedRegister(clientId: 'gone'));

    await queue.dismiss('gone');

    expect(phone.read(registerQueueProvider).unsent, isEmpty);
    expect(stored('register.unsent'), isEmpty);

    phone.dispose();
  });

  test('a corrupt saved entry reads as nothing rather than stopping the app', () async {
    final corrupt = InMemoryKeyValueStore();
    await corrupt.write('register.waiting', '{not json');
    await corrupt.write('register.roster.$sectionId', '[{"name": 3}]');

    expect(await RegisterStore(corrupt).readWaiting(), isEmpty);
    expect(await RegisterStore(corrupt).readRoster(sectionId), isNull);
  });

  test('a saved register reads back exactly as it was saved', () {
    final register = savedRegister();
    final back = register.toJson();
    final again = SavedRegister.fromJson(jsonDecode(jsonEncode(back)) as Map<String, dynamic>);

    expect(again.clientId, register.clientId);
    expect(again.marks, register.marks);
    expect(again.savedAt, register.savedAt);
    expect(again.records, register.records);
  });
}
