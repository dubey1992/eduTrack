import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/models/student_performance.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/presentation/student_performance_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_student_repository.dart';
import '../../support/session_users.dart';

/// A student's numbers (docs/assessments.md): a term at a time, the previous
/// one beside it, and nothing invented where there is nothing to say.
const _student = Student(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: 1,
  classSectionName: 'Grade 8 A',
  admissionNumber: 'STU-0042',
  firstName: 'Arjun',
  lastName: 'Kumar',
  name: 'Arjun Kumar',
  rollNumber: '12',
  guardianName: 'Raj Kumar',
  guardianMobile: '9876543210',
  address: null,
  status: StudentStatus.active,
);

Widget wrap(FakeStudentRepository fake, {UserRole role = UserRole.schoolAdmin}) {
  return ProviderScope(
    overrides: [
      studentRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
    ],
    retry: (retryCount, error) => null,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: StudentPerformanceDialog(student: _student)),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(2000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('the model', () {
    test('reads the term, the subjects and the register', () {
      final parsed = StudentPerformance.fromJson({
        'student': {'id': 1, 'name': 'Arjun Kumar', 'admission_number': 'STU-0042', 'class_section_name': 'Grade 8 A'},
        'term': {'id': 2, 'name': 'Term 2', 'sequence_number': 2, 'start_date': '2026-09-01', 'end_date': '2027-03-31'},
        'previous_term': {
          'id': 1,
          'name': 'Term 1',
          'sequence_number': 1,
          'start_date': '2026-04-01',
          'end_date': '2026-08-31',
        },
        'terms': [
          {'id': 2, 'name': 'Term 2', 'sequence_number': 2},
        ],
        'subjects': [
          {
            'subject_id': 5,
            'subject_name': 'Mathematics',
            'assessments': 3,
            'absent': 1,
            'average_percentage': '72.50',
            'grade': 'A2',
            'class_average_percentage': '65.00',
            'previous_average_percentage': '60.00',
            'change': '12.50',
          },
        ],
        'overall': {'subjects': 1, 'assessments': 3, 'absent': 1, 'average_percentage': '72.50'},
        'attendance': {
          'working_days': 20,
          'present': 18,
          'absent': 2,
          'leave': 0,
          'not_marked': 0,
          'attendance_rate': 90,
        },
        'weak_below_percentage': 40,
      });

      expect(parsed.term!.name, 'Term 2');
      expect(parsed.previousTerm!.name, 'Term 1');
      expect(parsed.subjects.single.averagePercentage, '72.50');
      expect(parsed.subjects.single.changeValue, 12.5);
      expect(parsed.overall.assessments, 3);
      expect(parsed.attendance.attendanceRate, 90);
      expect(parsed.hasMarks, isTrue);
    });

    test('a school with no term at all parses rather than throwing', () {
      final parsed = StudentPerformance.fromJson({
        'student': {'name': 'Arjun Kumar'},
        'term': null,
        'previous_term': null,
        'terms': [],
        'subjects': [],
        'overall': null,
        'attendance': null,
        'weak_below_percentage': null,
      });

      expect(parsed.term, isNull);
      expect(parsed.hasMarks, isFalse);
      expect(parsed.overall.subjects, 0);
      expect(parsed.attendance.attendanceRate, isNull);
    });

    test('weak is the school\'s own mark, and nothing is weak without one', () {
      const subject = SubjectPerformance(
        subjectId: 1,
        subjectName: 'Mathematics',
        assessments: 2,
        absent: 0,
        averagePercentage: '34.00',
      );

      expect(subject.isWeak(40), isTrue);
      expect(subject.isWeak(30), isFalse);
      expect(subject.isWeak(null), isFalse);
    });

    test('a subject with no average is never weak - nothing is not a low mark', () {
      const missed = SubjectPerformance(
        subjectId: 1,
        subjectName: 'Mathematics',
        assessments: 2,
        absent: 2,
        averagePercentage: null,
      );

      expect(missed.isWeak(40), isFalse);
    });
  });

  group('the dialog', () {
    testWidgets('shows the term, the subjects and the class average beside them', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
      await tester.pumpAndSettle();

      expect(find.text('Performance · Arjun Kumar'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);
      expect(find.text('34.00%'), findsOneWidget);
      expect(find.text('61.00%'), findsOneWidget, reason: 'the class average for the same tests');
      expect(find.text('Compared with Term 1'), findsOneWidget);
    });

    testWidgets('a subject under the school\'s mark is flagged', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
      await tester.pumpAndSettle();

      // Mathematics at 34% against a 40% mark; Science at 78% is not.
      expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    });

    testWidgets('a fall and a rise read differently', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.text('14.00'), findsOneWidget);
    });

    testWidgets('the missed tests are said, not hidden', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
      await tester.pumpAndSettle();

      expect(find.text('3 (1 missed)'), findsOneWidget);
    });

    testWidgets('the register for the same period sits underneath', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
      await tester.pumpAndSettle();

      expect(find.text('Attendance this term'), findsOneWidget);
      expect(find.text('70.0%'), findsOneWidget);
      expect(find.text('School days'), findsOneWidget);
    });

    testWidgets('choosing another term asks the server for it', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository(students: [_student]);

      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('performance-term')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Term 1').last);
      await tester.pumpAndSettle();

      expect(fake.termCalls, [null, 1], reason: 'the first call takes whatever term the school is in');
    });

    testWidgets('a term with no published result says so rather than showing zeros', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakeStudentRepository(
            students: [_student],
            performance: fakePerformance(
              subjects: const [],
              overall: const OverallPerformance(subjects: 0, assessments: 0, absent: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No published result in Term 2 yet'), findsOneWidget);
      expect(find.text('0.00%'), findsNothing);
    });

    testWidgets('a school with no terms is told so plainly', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakeStudentRepository(
            students: [_student],
            performance: fakePerformance(withoutTerm: true, terms: const [], subjects: const []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('has no terms yet'), findsOneWidget);
    });

    testWidgets('a first term has nothing to compare against, and says that too', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(FakeStudentRepository(students: [_student], performance: fakePerformance(withoutPreviousTerm: true))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing before this term to compare with'), findsOneWidget);
    });

    testWidgets('a period with no school day yet shows no percentage', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakeStudentRepository(
            students: [_student],
            performance: fakePerformance(
              attendance: const PerformanceAttendance(workingDays: 0, present: 0, absent: 0, leave: 0, notMarked: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No school days in this period yet.'), findsOneWidget);
    });

    testWidgets('a server that refuses is shown with a way to try again', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(FakeStudentRepository(students: [_student], failWith: {'performance': Failure.network()})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not reach the server. Check your connection and try again.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    });

    testWidgets('a school with class tests switched off is told that, not shown an error', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakeStudentRepository(
            students: [_student],
            failWith: {
              'performance': const Failure(
                code: 'MODULE_DISABLED',
                message: 'Class Tests & Assessments is switched off for this school.',
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Class Tests & Assessments is switched off for this school.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsNothing, reason: 'a switch is not a fault to retry');
    });
  });

  group('the insights', () {
    testWidgets('are read as sentences, with the concerning ones marked', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
      await tester.pumpAndSettle();

      expect(find.text('What this looks like'), findsOneWidget);
      expect(find.text("Mathematics is at 34%, below the school's 40% mark."), findsOneWidget);
      expect(find.text('Science is up 12 points since Term 1.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget, reason: 'the weak one');
      expect(find.byIcon(Icons.trending_up), findsOneWidget, reason: 'the improving one');
    });

    testWidgets('a steady term shows no heading at all rather than an empty one', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          FakeStudentRepository(
            students: [_student],
            performance: fakePerformance(insights: const []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('What this looks like'), findsNothing);
    });

    test('an insight parses with everything it was drawn from', () {
      final parsed = PerformanceInsight.fromJson(const {
        'code': 'slipping',
        'message': 'Science has fallen 14 points since Term 1.',
        'subject_id': 2,
        'subject_name': 'Science',
        'numbers': {'change': '-14', 'average': '52', 'previous': '66'},
      });

      expect(parsed.code, 'slipping');
      expect(parsed.subjectName, 'Science');
      expect(parsed.numbers['previous'], '66');
      expect(parsed.isConcerning, isTrue);
    });

    test('only improvement reads as good news', () {
      const improving = PerformanceInsight(code: 'improving', message: 'up');
      const missed = PerformanceInsight(code: 'missed_tests', message: 'absent');

      expect(improving.isConcerning, isFalse);
      expect(missed.isConcerning, isTrue);
    });
  });

  group('who is offered it', () {
    test('a school with the assessments module off does not see the action', () {
      final off = sessionUser(UserRole.teacher, modules: {AppModules.assessments: false});
      final on = sessionUser(UserRole.teacher);

      expect(off.moduleOn(AppModules.assessments), isFalse);
      expect(on.moduleOn(AppModules.assessments), isTrue);
    });
  });

  group('the printable report', () {
    testWidgets('is offered once there is a result, and asks for the term on screen', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository();
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Download PDF'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Download PDF'));
      await tester.pumpAndSettle();

      expect(fake.progressReportCalls, [
        2,
      ], reason: 'the term the dialog is showing, not whichever the server would pick');
    });

    testWidgets('is not offered for a term with nothing published', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository(performance: fakePerformance(subjects: const []));
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      // A sheet reading "nothing published yet" wastes somebody's paper.
      expect(find.widgetWithText(OutlinedButton, 'Download PDF'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    });

    testWidgets('says why when the download fails, rather than failing quietly', (tester) async {
      useDesktop(tester);
      final fake = FakeStudentRepository(
        failWith: {'progressReport': const Failure(code: 'SERVER_ERROR', message: 'The report could not be built.')},
      );
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Download PDF'));
      await tester.pumpAndSettle();

      expect(find.text('The report could not be built.'), findsOneWidget);
      // And the button comes back, so it can be tried again.
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Download PDF')).onPressed, isNotNull);
    });
  });

  testWidgets('a term nobody took the register for says so rather than showing 0%', (tester) async {
    useDesktop(tester);
    final fake = FakeStudentRepository(
      performance: fakePerformance(
        attendance: const PerformanceAttendance(
          workingDays: 22,
          present: 0,
          absent: 0,
          leave: 0,
          notMarked: 22,
          attendanceRate: 0,
        ),
      ),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    // 0% is the truth about the school's paperwork. Under a child's name it
    // reads as a child who attended nothing, and the progress report says
    // the same sentence for the same reason.
    expect(find.textContaining('The register was not taken in this period'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  group('inside each subject', () {
    const weakMaths = SubjectPerformance(
      subjectId: 1,
      subjectName: 'Mathematics',
      assessments: 3,
      absent: 1,
      averagePercentage: '52.00',
      grade: 'Pass',
      topics: [
        TopicPerformance(topicId: 1, topicName: 'Vectors', assessments: 1, absent: 0, averagePercentage: '72.00'),
        TopicPerformance(topicId: 2, topicName: 'Trigonometry', assessments: 1, absent: 0, averagePercentage: '38.00'),
        TopicPerformance(topicId: 3, topicName: 'Calculus', assessments: 1, absent: 1),
      ],
    );

    testWidgets('names the chapters a subject average hides', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeStudentRepository(performance: fakePerformance(subjects: [weakMaths]))));
      await tester.pumpAndSettle();

      expect(find.text('Inside each subject'), findsOneWidget);
      expect(find.text('Vectors'), findsOneWidget);
      expect(find.text('Trigonometry'), findsOneWidget);
      expect(find.text('72.00%'), findsOneWidget);
      expect(find.text('38.00%'), findsOneWidget);
    });

    testWidgets('a topic nobody has measured reads as not sat, never as nought', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeStudentRepository(performance: fakePerformance(subjects: [weakMaths]))));
      await tester.pumpAndSettle();

      expect(find.text('Calculus'), findsOneWidget);
      expect(find.text('not sat'), findsOneWidget);
      expect(find.text('0.00%'), findsNothing, reason: 'a topic they were absent for is not a zero');
    });

    testWidgets('a school that names no topics sees no section rather than an empty one', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeStudentRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Inside each subject'), findsNothing);
    });

    test("a topic is weak against the school's own mark, and an unmeasured one never is", () {
      const trig = TopicPerformance(
        topicId: 2,
        topicName: 'Trigonometry',
        assessments: 1,
        absent: 0,
        averagePercentage: '38.00',
      );
      const missed = TopicPerformance(topicId: 3, topicName: 'Calculus', assessments: 1, absent: 1);

      expect(trig.isWeak(40), isTrue);
      expect(trig.isWeak(30), isFalse);
      expect(trig.isWeak(null), isFalse, reason: 'a school that keeps no mark flags nothing');
      expect(missed.isWeak(40), isFalse, reason: 'nobody has measured it, so it cannot be weak');
    });
  });

  group('what to do next', () {
    const steps = [
      PerformanceInsight(
        code: 'revise_topics',
        message: 'Revise Trigonometry in Mathematics before the next test.',
        subjectId: 1,
        subjectName: 'Mathematics',
      ),
      PerformanceInsight(code: 'arrange_resit', message: 'Offer a re-sit for the 2 tests missed, of 6 this term.'),
    ];

    testWidgets('each suggestion is shown under its own heading', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeStudentRepository(performance: fakePerformance(recommendations: steps))));
      await tester.pumpAndSettle();

      expect(find.text('What to do next'), findsOneWidget);
      expect(find.text('Revise Trigonometry in Mathematics before the next test.'), findsOneWidget);
      expect(find.text('Offer a re-sit for the 2 tests missed, of 6 this term.'), findsOneWidget);
    });

    testWidgets('a term with nothing to suggest shows no heading at all', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeStudentRepository(performance: fakePerformance(recommendations: const []))));
      await tester.pumpAndSettle();

      expect(find.text('What to do next'), findsNothing);
    });

    testWidgets('it is kept apart from what the figures say', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          FakeStudentRepository(
            performance: fakePerformance(
              insights: const [PerformanceInsight(code: 'weak_subject', message: 'Mathematics is at 34%.')],
              recommendations: steps,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A guardian reading this should be able to tell what the school is
      // saying from what it is suggesting.
      expect(find.text('What this looks like'), findsOneWidget);
      expect(find.text('What to do next'), findsOneWidget);
    });
  });

  group('sending it to the guardian', () {
    Future<void> openAndSend(WidgetTester tester, FakeStudentRepository fake, {bool confirm = true}) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Send to guardian'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(confirm ? FilledButton : TextButton, confirm ? 'Send' : 'Cancel'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, then sends the term on screen', (tester) async {
      final fake = FakeStudentRepository();
      await openAndSend(tester, fake);

      expect(fake.sendCalls, [2], reason: 'the term the dialog is showing');
      expect(find.text('Progress report sent to the guardian.'), findsOneWidget);
    });

    testWidgets('saying no sends nothing', (tester) async {
      final fake = FakeStudentRepository();
      await openAndSend(tester, fake, confirm: false);

      expect(fake.sendCalls, isEmpty, reason: 'a document about a child does not go out on a mistaken tap');
    });

    testWidgets('the warning says what the guardian will see', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeStudentRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Send to guardian'));
      await tester.pumpAndSettle();

      expect(find.textContaining('will be emailed to their guardian'), findsOneWidget);
      expect(find.textContaining('every figure on this page'), findsOneWidget);
    });

    testWidgets('a school with email switched off is told why', (tester) async {
      final fake = FakeStudentRepository(
        failWith: {
          'sendProgressReport': const Failure(
            code: 'EMAIL_NOT_SENT',
            message: 'Email is switched off for this school, so nothing was sent.',
          ),
        },
      );
      await openAndSend(tester, fake);

      expect(find.text('Email is switched off for this school, so nothing was sent.'), findsOneWidget);
    });

    testWidgets('it is not offered for a term with nothing published', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeStudentRepository(performance: fakePerformance(subjects: const []))));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Send to guardian'), findsNothing);
    });
  });
}
