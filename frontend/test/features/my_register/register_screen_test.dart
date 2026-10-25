import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_status.dart';
import 'package:edutrack_app/features/my_register/data/models/saved_register.dart';
import 'package:edutrack_app/features/my_register/data/register_store.dart';
import 'package:edutrack_app/features/my_register/presentation/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import 'register_fixtures.dart';

/// The register screen on the phone (docs/teacher-app.md, T2).
void main() {
  late FakeAttendanceRepository attendance;
  late InMemoryKeyValueStore store;

  setUp(() {
    attendance = FakeAttendanceRepository(register: registerOf());
    store = InMemoryKeyValueStore();
  });

  Future<void> pump(WidgetTester tester, {ThemeData? theme}) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: registerOverrides(attendance, store),
        child: MaterialApp(
          theme: theme ?? AppTheme.teacherLight(),
          home: const RegisterScreen(registerKey: (sectionId: sectionId, date: day, label: 'Grade 3 A')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String tally(WidgetTester tester, String which) {
    final texts = tester.widgetList<Text>(
      find.descendant(of: find.byKey(Key('register-tally-$which')), matching: find.byType(Text)),
    );
    return texts.first.data!;
  }

  FilledButton submitButton(WidgetTester tester) => tester.widget(find.byKey(const Key('register-submit')));

  testWidgets('shows the class, the date and every student, all unmarked', (tester) async {
    await pump(tester);

    expect(find.text('Grade 3 A register'), findsOneWidget);
    expect(find.text('Monday, October 26'), findsOneWidget);
    for (final name in ['Aarav Shah', 'Diya Patel', 'Kabir Rao']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(tally(tester, 'unmarked'), '3');
    expect(find.text('Mark everyone (3 left)'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull, reason: 'nobody is left out by accident');
  });

  testWidgets('the tally follows every mark, and Submit opens once everyone is marked', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('register-2-absent')));
    await tester.pump();
    expect(tally(tester, 'absent'), '1');
    expect(tally(tester, 'unmarked'), '2');

    await tester.tap(find.byKey(const Key('register-2-leave')));
    await tester.pump();
    expect(tally(tester, 'absent'), '0', reason: 'changing a mark moves it, it does not add one');
    expect(tally(tester, 'leave'), '1');

    await tester.tap(find.byKey(const Key('register-all-present')));
    await tester.pump();
    expect(tally(tester, 'present'), '2');
    expect(tally(tester, 'leave'), '1', reason: 'All present leaves marks already made');
    expect(tally(tester, 'unmarked'), '0');
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('Submit asks first with the counts, and Check again sends nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('register-all-present')));
    await tester.tap(find.byKey(const Key('register-3-absent')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-confirm')), findsOneWidget);
    expect(find.textContaining('2 present, 1 absent.'), findsOneWidget);
    expect(find.textContaining('Parents of absent children are told'), findsOneWidget);

    await tester.tap(find.byKey(const Key('register-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(attendance.submitCallCount, 0);
    expect(find.byKey(const Key('register-submit')), findsOneWidget, reason: 'still taking it');
  });

  testWidgets('submitted with signal: says so, and the register is shown as taken', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('register-all-present')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('register-confirm-submit')));
    await tester.pumpAndSettle();

    expect(attendance.submitCallCount, 1);
    expect(find.text('Register submitted.'), findsOneWidget);
    expect(find.byKey(const Key('register-submitted')), findsOneWidget);
    expect(find.byKey(const Key('register-correct')), findsOneWidget);
  });

  testWidgets('submitted without signal: saved on the phone, and the screen says it is waiting', (tester) async {
    attendance.failSubmitWith = Failure.network();
    await pump(tester);
    await tester.tap(find.byKey(const Key('register-all-present')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('register-confirm-submit')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('saved on this phone and sent when there is'), findsOneWidget);
    expect(find.byKey(const Key('register-waiting')), findsOneWidget);
    expect(find.text('Waiting for signal to send.'), findsOneWidget);
    // Nothing can be changed while it waits: what was submitted is what goes.
    final present = tester.widget<OutlinedButton>(find.byKey(const Key('register-1-present')));
    expect(present.onPressed, isNull);

    // Let the back-off timer run out cleanly.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets("refused: stays open with the server's reason", (tester) async {
    attendance.failSubmitWith = alreadyTaken;
    await pump(tester);
    await tester.tap(find.byKey(const Key('register-all-present')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('register-confirm-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-refused')), findsOneWidget);
    expect(find.text('Not sent: Attendance has already been submitted.'), findsOneWidget);
    expect(find.byKey(const Key('register-submit')), findsOneWidget);
  });

  testWidgets('no signal, class opened before: taken as usual, with a note', (tester) async {
    await RegisterStore(store)
        .saveRoster(sectionId, const [CachedStudent(studentId: 1, name: 'Aarav Shah', rollNumber: '1')]);
    attendance.failRegisterWith = Failure.network();
    await pump(tester);

    expect(find.byKey(const Key('register-offline')), findsOneWidget);
    expect(find.text('Aarav Shah'), findsOneWidget);
  });

  testWidgets('no signal, class never opened here: the error says what to do, with Retry', (tester) async {
    attendance.failRegisterWith = Failure.network();
    await pump(tester);

    expect(find.textContaining('Open the register once with signal'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    attendance.failRegisterWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Diya Patel'), findsOneWidget);
  });

  testWidgets('a holiday shows there is no register to take', (tester) async {
    attendance = FakeAttendanceRepository(register: holidayRegister());
    await pump(tester);

    expect(find.byKey(const Key('register-closed')), findsOneWidget);
    expect(find.text('Holiday: Diwali'), findsOneWidget);
    expect(find.byKey(const Key('register-submit')), findsNothing);
  });

  testWidgets('a taken day can be corrected and saved', (tester) async {
    attendance = FakeAttendanceRepository(
      register: registerOf(
        submitted: true,
        marks: const {1: AttendanceStatus.present, 2: AttendanceStatus.absent, 3: AttendanceStatus.present},
      ),
    );
    await pump(tester);
    expect(tally(tester, 'absent'), '1');

    await tester.tap(find.byKey(const Key('register-correct')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-2-present')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-save-correction')));
    await tester.pumpAndSettle();

    expect(find.text('Register corrected.'), findsOneWidget);
    expect(find.byKey(const Key('register-submitted')), findsOneWidget);
    expect(tally(tester, 'absent'), '0');
  });

  testWidgets('a correction without signal says it needs a connection, and keeps the changes', (tester) async {
    attendance = FakeAttendanceRepository(
      register: registerOf(
        submitted: true,
        marks: const {1: AttendanceStatus.present, 2: AttendanceStatus.absent, 3: AttendanceStatus.present},
      ),
      failUpdateWith: Failure.network(),
    );
    await pump(tester);

    await tester.tap(find.byKey(const Key('register-correct')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-2-present')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('register-save-correction')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-problem')), findsOneWidget);
    expect(find.textContaining('A correction needs a connection'), findsOneWidget);
    expect(tally(tester, 'absent'), '0', reason: 'the change is still there to save again');
    expect(find.byKey(const Key('register-save-correction')), findsOneWidget);
  });

  testWidgets('fits a phone in the dark theme without overflow', (tester) async {
    await pump(tester, theme: AppTheme.teacherDark());
    await tester.tap(find.byKey(const Key('register-all-present')));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
