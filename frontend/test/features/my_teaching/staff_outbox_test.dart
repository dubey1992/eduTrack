import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_teaching/application/staff_outbox.dart';
import 'package:edutrack_app/features/my_teaching/data/outbox.dart';
import 'package:edutrack_app/features/my_teaching/data/report_notes.dart';
import 'package:edutrack_app/features/teaching_reports/data/teaching_report_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assessment_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_teaching_report_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

/// Reports and marks saved with no signal, sent when there is some
/// (docs/mobile-apps-review.md, 2.1). The queue runs on timers, so these
/// are widget tests: `tester.pump(duration)` moves the clock.
void main() {
  late InMemoryKeyValueStore store;
  late FakeTeachingReportRepository reports;
  late FakeAssessmentRepository marks;

  setUp(() {
    store = InMemoryKeyValueStore();
    reports = FakeTeachingReportRepository();
    marks = FakeAssessmentRepository();
  });

  Future<ProviderContainer> phone({int signedIn = 7}) async {
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        teachingReportRepositoryProvider.overrideWithValue(reports),
        assessmentRepositoryProvider.overrideWithValue(marks),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, id: signedIn)),
        ),
      ],
    );
    await container.read(authNotifierProvider.future);
    container.listen(staffOutboxProvider, (_, _) {});
    return container;
  }

  OutboxItem report({int userId = 7, String topic = 'Fractions'}) => OutboxItem(
    kind: OutboxKind.report,
    key: OutboxItem.reportKey(11, '2026-10-26'),
    userId: userId,
    label: 'Mathematics, Grade 3 A, period 1',
    payload: {'timetable_entry_id': 11, 'report_date': '2026-10-26', 'topic_taught': topic},
    savedAt: DateTime(2026, 10, 26, 10),
  );

  OutboxItem sheet(String marksObtained) => OutboxItem(
    kind: OutboxKind.marks,
    key: OutboxItem.marksKey(4),
    userId: 7,
    label: 'Marks: Unit test 1',
    payload: {
      'assessment_id': 4,
      'marks': [
        {'student_id': 1, 'marks_obtained': marksObtained, 'is_absent': false, 'remarks': null},
      ],
    },
    savedAt: DateTime(2026, 10, 26, 10),
  );

  testWidgets('a saved report is sent, and leaves the outbox', (tester) async {
    final container = await phone();

    await container.read(staffOutboxProvider.notifier).add(report());
    await tester.pump();

    expect(reports.lastStorePayload?['topic_taught'], 'Fractions');
    expect(container.read(staffOutboxProvider), isEmpty);
    expect(await OutboxStore(store).read(), isEmpty);
    container.dispose();
  });

  testWidgets('with no signal it waits, and goes when signal is back', (tester) async {
    reports.failStoreWith = Failure.network();
    final container = await phone();

    await container.read(staffOutboxProvider.notifier).add(report());
    await tester.pump();
    expect(container.read(staffOutboxProvider), hasLength(1));

    reports.failStoreWith = null;
    await tester.pump(StaffOutbox.retryDelays.first);

    expect(container.read(staffOutboxProvider), isEmpty);
    container.dispose();
  });

  testWidgets('a report the server already has is done, not a failure', (tester) async {
    reports.failStoreWith = const Failure(code: 'TEACHING_REPORT_ALREADY_SUBMITTED', message: 'Already filed.');
    final container = await phone();

    await container.read(staffOutboxProvider.notifier).add(report());
    await tester.pump();

    expect(container.read(staffOutboxProvider), isEmpty);
    container.dispose();
  });

  testWidgets('a refusal is kept with its reason, and the words go back into the draft', (tester) async {
    reports.failStoreWith = const Failure(code: 'CHECK_IN_REQUIRED', message: 'Check in first.');
    final container = await phone();

    await container.read(staffOutboxProvider.notifier).add(report());
    await tester.pump();

    final kept = container.read(staffOutboxProvider).single;
    expect(kept.refusal, 'Check in first.');
    expect((await ReportNotes(store).draft(11, '2026-10-26'))?.topic, 'Fractions');

    // Not tried again on its own: the reason will not change by waiting.
    reports.failStoreWith = null;
    await tester.pump(const Duration(minutes: 2));
    expect(reports.lastStorePayload, isNull);
    container.dispose();
  });

  testWidgets('the newest marks for a test replace any saved before them', (tester) async {
    marks = FakeAssessmentRepository(failWith: {'saveMarks': Failure.network()});
    final container = await phone();
    final outbox = container.read(staffOutboxProvider.notifier);

    await outbox.add(sheet('10'));
    await outbox.add(sheet('12'));
    await tester.pump();

    expect(container.read(staffOutboxProvider), hasLength(1));
    expect((container.read(staffOutboxProvider).single.payload['marks'] as List).single['marks_obtained'], '12');
    container.dispose();
  });

  testWidgets("saved marks are sent as the teacher's whole sheet", (tester) async {
    final container = await phone();

    await container.read(staffOutboxProvider.notifier).add(sheet('12'));
    await tester.pump();

    expect(marks.lastSaved?.single.marksObtained, '12');
    expect(container.read(staffOutboxProvider), isEmpty);
    container.dispose();
  });

  testWidgets("another teacher's saved work stays put under this sign-in", (tester) async {
    await OutboxStore(store).save([report(userId: 99)]);
    final container = await phone();

    await container.read(staffOutboxProvider.notifier).retryNow();
    await tester.pump();

    expect(reports.lastStorePayload, isNull);
    expect(container.read(staffOutboxProvider), hasLength(1));
    container.dispose();
  });

  testWidgets('survives the app being closed', (tester) async {
    reports.failStoreWith = Failure.network();
    final first = await phone();
    await first.read(staffOutboxProvider.notifier).add(report());
    await tester.pump();
    first.dispose();

    reports.failStoreWith = null;
    final again = await phone();
    await again.read(staffOutboxProvider.notifier).retryNow();
    await tester.pump();

    expect(reports.lastStorePayload?['topic_taught'], 'Fractions');
    again.dispose();
  });
}
