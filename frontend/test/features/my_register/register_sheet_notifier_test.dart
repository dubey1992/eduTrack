import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_status.dart';
import 'package:edutrack_app/features/holidays/data/models/holiday.dart';
import 'package:edutrack_app/features/my_register/application/register_sheet_notifier.dart';
import 'package:edutrack_app/features/my_register/data/models/saved_register.dart';
import 'package:edutrack_app/features/my_register/data/register_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import 'register_fixtures.dart';

/// One class's register on the phone (docs/teacher-app.md, T2): where it
/// opens, and what each action does.
void main() {
  const key = (sectionId: sectionId, date: day, label: 'Grade 3 A');

  late FakeAttendanceRepository attendance;
  late InMemoryKeyValueStore store;

  setUp(() {
    attendance = FakeAttendanceRepository(register: registerOf());
    store = InMemoryKeyValueStore();
  });

  Future<(ProviderContainer, RegisterSheet)> open() async {
    final phone = await signedInPhone(attendance, store);
    addTearDown(phone.dispose);
    // Held open, as the screen holds it; autoDispose would drop it otherwise.
    phone.listen(registerSheetProvider(key), (_, _) {});
    return (phone, await phone.read(registerSheetProvider(key).future));
  }

  group('opening', () {
    test('a day not yet taken opens unmarked, and keeps the class list for no signal', () async {
      final (_, sheet) = await open();

      expect(sheet.mode, RegisterMode.taking);
      expect(sheet.students.map((s) => s.name), ['Aarav Shah', 'Diya Patel', 'Kabir Rao']);
      expect(sheet.unmarked, 3);
      expect(sheet.complete, isFalse);
      expect(attendance.lastRegisterDate, day, reason: "the school's date from Today, not the phone's");
      expect(await RegisterStore(store).readRoster(sectionId), hasLength(3));
    });

    test('a day already taken opens with its marks, and cannot be changed without Correct', () async {
      attendance = FakeAttendanceRepository(
        register: registerOf(
          submitted: true,
          marks: const {1: AttendanceStatus.present, 2: AttendanceStatus.absent, 3: AttendanceStatus.leave},
        ),
      );
      final (phone, sheet) = await open();

      expect(sheet.mode, RegisterMode.submitted);
      expect(sheet.count(AttendanceStatus.absent), 1);
      expect(sheet.editable, isFalse);

      phone.read(registerSheetProvider(key).notifier).setMark(2, AttendanceStatus.present);
      expect(phone.read(registerSheetProvider(key)).value!.count(AttendanceStatus.absent), 1);
    });

    test('a holiday opens closed, with its name', () async {
      attendance = FakeAttendanceRepository(
        register: AttendanceRegister(
          classSectionId: sectionId,
          attendanceDate: day,
          submitted: false,
          students: registerOf().students,
          holiday: const HolidaySummary(id: 1, name: 'Diwali', type: HolidayType.religious),
        ),
      );
      final (_, sheet) = await open();

      expect(sheet.mode, RegisterMode.closed);
      expect(sheet.holidayName, 'Diwali');
    });

    test('without signal, a class opened before opens from the phone', () async {
      await RegisterStore(store)
          .saveRoster(sectionId, const [CachedStudent(studentId: 1, name: 'Aarav Shah', rollNumber: '1')]);
      attendance.failRegisterWith = Failure.network();

      final (_, sheet) = await open();

      expect(sheet.mode, RegisterMode.taking);
      expect(sheet.offline, isTrue);
      expect(sheet.students.single.name, 'Aarav Shah');
    });

    test('without signal, a class never opened on this phone says how to fix it', () async {
      attendance.failRegisterWith = Failure.network();
      final phone = await signedInPhone(attendance, store);
      addTearDown(phone.dispose);
      phone.listen(registerSheetProvider(key), (_, _) {});

      await expectLater(
        phone.read(registerSheetProvider(key).future),
        throwsA(isA<Failure>().having((f) => f.message, 'message', contains('Open the register once with signal'))),
      );
    });

    test('any other error is shown as it is, not covered up by the saved list', () async {
      await RegisterStore(store)
          .saveRoster(sectionId, const [CachedStudent(studentId: 1, name: 'Aarav Shah', rollNumber: '1')]);
      attendance.failRegisterWith = const Failure(code: 'FORBIDDEN', message: 'Not your class.');
      final phone = await signedInPhone(attendance, store);
      addTearDown(phone.dispose);
      phone.listen(registerSheetProvider(key), (_, _) {});

      await expectLater(phone.read(registerSheetProvider(key).future), throwsA(isA<Failure>()));
    });

    test('a register waiting on the phone opens as waiting, with its marks', () async {
      await RegisterStore(store).saveWaiting([savedRegister()]);
      // No signal, so it stays waiting while the sheet opens.
      attendance.failSubmitWith = Failure.network();

      final (_, sheet) = await open();

      expect(sheet.mode, RegisterMode.waiting);
      expect(sheet.count(AttendanceStatus.absent), 1);
      expect(sheet.editable, isFalse);
    });
  });

  group('marking', () {
    test('All present fills only the students not yet marked', () async {
      final (phone, _) = await open();
      final notifier = phone.read(registerSheetProvider(key).notifier);

      notifier.setMark(2, AttendanceStatus.absent);
      notifier.markAllPresent();

      final sheet = phone.read(registerSheetProvider(key)).value!;
      expect(sheet.marks, {1: AttendanceStatus.present, 2: AttendanceStatus.absent, 3: AttendanceStatus.present});
      expect(sheet.complete, isTrue);
    });

    test('an incomplete register is not submitted', () async {
      final (phone, _) = await open();
      final notifier = phone.read(registerSheetProvider(key).notifier);
      notifier.setMark(1, AttendanceStatus.present);

      expect(await notifier.submit(), RegisterMode.taking);
      expect(attendance.submitCallCount, 0);
    });

    test('a complete register with signal is submitted', () async {
      final (phone, _) = await open();
      final notifier = phone.read(registerSheetProvider(key).notifier);
      notifier.markAllPresent();

      expect(await notifier.submit(), RegisterMode.submitted);
      expect(phone.read(registerSheetProvider(key)).value!.mode, RegisterMode.submitted);
    });

    test('without signal it waits on the phone', () async {
      final (phone, _) = await open();
      final notifier = phone.read(registerSheetProvider(key).notifier);
      notifier.markAllPresent();
      attendance.failSubmitWith = Failure.network();

      expect(await notifier.submit(), RegisterMode.waiting);
      expect(phone.read(registerSheetProvider(key)).value!.editable, isFalse);
    });

    test("refused, it stays open with the server's reason", () async {
      final (phone, _) = await open();
      final notifier = phone.read(registerSheetProvider(key).notifier);
      notifier.markAllPresent();
      attendance.failSubmitWith = alreadyTaken;

      expect(await notifier.submit(), RegisterMode.taking);
      expect(phone.read(registerSheetProvider(key)).value!.refusal, 'Attendance has already been submitted.');
    });
  });

  group('correcting', () {
    setUp(() {
      attendance = FakeAttendanceRepository(
        register: registerOf(
          submitted: true,
          marks: const {1: AttendanceStatus.present, 2: AttendanceStatus.absent, 3: AttendanceStatus.present},
        ),
      );
    });

    test('Correct, change a mark, and the change is saved to the server', () async {
      final (phone, _) = await open();
      final notifier = phone.read(registerSheetProvider(key).notifier);

      notifier.startCorrecting();
      notifier.setMark(2, AttendanceStatus.present);
      await notifier.saveCorrection();

      expect(attendance.lastUpdatePayload!['records'], contains(equals({'student_id': 2, 'status': 'present'})));
      expect(phone.read(registerSheetProvider(key)).value!.mode, RegisterMode.submitted);
    });

    test('a correction needs signal, and stays open when there is none', () async {
      final (phone, _) = await open();
      final notifier = phone.read(registerSheetProvider(key).notifier);
      attendance.failUpdateWith = Failure.network();

      notifier.startCorrecting();
      await expectLater(notifier.saveCorrection(), throwsA(isA<Failure>()));
      expect(phone.read(registerSheetProvider(key)).value!.mode, RegisterMode.correcting);
    });
  });
}
