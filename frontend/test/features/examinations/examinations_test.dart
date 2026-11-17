import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/examinations/data/examination_repository.dart';
import 'package:edutrack_app/features/examinations/data/models/examination.dart';
import 'package:edutrack_app/features/examinations/presentation/admit_cards_tab.dart';
import 'package:edutrack_app/features/examinations/presentation/examination_detail_screen.dart';
import 'package:edutrack_app/features/examinations/presentation/examination_list_screen.dart';
import 'package:edutrack_app/features/subjects/data/models/subject.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_subject_repository.dart';
import '../../support/session_users.dart';
import '../../support/viewed_year_overrides.dart';

/// Examinations and admit cards (docs/examinations.md): the screens a school
/// sets an exam up on, publishes it from and prints its cards from.
final year = AcademicYear(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise',
  name: '2026-27',
  startDate: DateTime(2026, 4, 1),
  endDate: DateTime(2027, 3, 31),
  isCurrent: true,
);

Examination exam({
  int id = 7,
  int version = 0,
  bool changes = false,
  List<ExamPaper> papers = const [],
  List<ExamVersion> versions = const [],
}) => Examination(
  id: id,
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Half-Yearly Examination',
  centre: 'Main Campus',
  reportingTime: '08:30',
  status: version > 0 ? 'published' : 'draft',
  version: version,
  hasUnpublishedChanges: changes,
  paperCount: papers.length,
  classCount: papers.map((p) => p.schoolClassId).toSet().length,
  papers: papers,
  versions: versions,
);

const englishPaper = ExamPaper(
  schoolClassId: 8,
  schoolClassName: 'Class 8',
  subjectId: 1,
  subjectName: 'English',
  examDate: '2026-12-07',
  startTime: '09:00',
  endTime: '12:00',
);

ExamCandidate candidate(int id, String name, CardState state, {String? reason, String? exception}) => ExamCandidate(
  studentId: id,
  name: name,
  admissionNumber: 'ADM-$id',
  className: 'Class 8',
  sectionId: 81,
  sectionName: 'A',
  rollNumber: '$id',
  state: state,
  reason: reason,
  exception: exception,
);

class FakeExaminationRepository implements ExaminationRepository {
  FakeExaminationRepository({List<Examination>? exams, this.candidateRows = const [], this.failWith = const {}})
    : exams = exams ?? [];

  final List<Examination> exams;
  List<ExamCandidate> candidateRows;
  final Map<String, Failure> failWith;
  final List<String> calls = [];
  Map<String, dynamic>? lastFields;
  List<ExamPaper>? lastPapers;
  ({int studentId, String? kind, String? reason})? lastException;
  ({int studentId, bool draft})? lastCard;
  int? lastSection;
  final List<String> saved = [];

  void _enter(String name) {
    calls.add(name);
    final failure = failWith[name];
    if (failure != null) throw failure;
  }

  Examination _find(int id) => exams.firstWhere((e) => e.id == id);

  void _replace(Examination updated) => exams[exams.indexWhere((e) => e.id == updated.id)] = updated;

  @override
  Future<PaginatedResponse<Examination>> list({int? academicYearId, int page = 1}) async {
    _enter('list');
    return PaginatedResponse(items: exams, currentPage: 1, lastPage: 1, total: exams.length, perPage: 20);
  }

  @override
  Future<Examination> get(int id) async {
    _enter('get');
    return _find(id);
  }

  @override
  Future<Examination> create(Map<String, dynamic> fields) async {
    _enter('create');
    lastFields = fields;
    final created = exam(id: 99);
    exams.add(created);
    return created;
  }

  @override
  Future<Examination> update(int id, Map<String, dynamic> fields) async {
    _enter('update');
    lastFields = fields;
    return _find(id);
  }

  @override
  Future<void> delete(int id) async => _enter('delete');

  @override
  Future<Examination> savePapers(int id, List<ExamPaper> papers) async {
    _enter('savePapers');
    lastPapers = papers;
    final current = _find(id);
    final updated = exam(id: id, version: current.version, changes: current.isPublished, papers: papers);
    _replace(updated);
    return updated;
  }

  @override
  Future<Examination> publish(int id) async {
    _enter('publish');
    final current = _find(id);
    final updated = exam(id: id, version: current.version + 1, papers: current.papers);
    _replace(updated);
    return updated;
  }

  @override
  Future<CandidatePage> candidates(int id, {int? sectionId, String? query, CardState? state, int page = 1}) async {
    _enter('candidates');
    final rows = candidateRows.where((row) => state == null || row.state == state).toList();
    final counts = <CardState, int>{};
    for (final row in candidateRows) {
      counts[row.state] = (counts[row.state] ?? 0) + 1;
    }
    return CandidatePage(items: rows, currentPage: 1, lastPage: 1, total: rows.length, counts: counts);
  }

  @override
  Future<String> setException(int id, {required int studentId, String? kind, String? reason}) async {
    _enter('setException');
    lastException = (studentId: studentId, kind: kind, reason: reason);
    return kind == 'withhold' ? 'withheld' : 'ready';
  }

  @override
  Future<List<int>> card(int id, int studentId, {bool draft = false, int? version}) async {
    _enter('card');
    lastCard = (studentId: studentId, draft: draft);
    return const [37, 80, 68, 70];
  }

  @override
  Future<CardBatch> sectionCards(int id, {required int sectionId}) async {
    _enter('sectionCards');
    lastSection = sectionId;
    return const CardBatch(bytes: [1], fileName: 'cards.pdf', printed: 2, skipped: 1);
  }
}

final classes = [
  const SchoolClass(
    id: 8,
    schoolId: 1,
    schoolName: 'Sunrise',
    academicYearId: 1,
    academicYearName: '2026-27',
    name: 'Class 8',
    level: 8,
    sections: [
      ClassSection(id: 81, schoolClassId: 8, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
    ],
  ),
];

final subjects = [
  const Subject(
    id: 1,
    schoolId: 1,
    schoolName: 'Sunrise',
    departmentId: 1,
    departmentName: 'Languages',
    code: 'ENG',
    name: 'English',
    minClassLevel: 1,
    maxClassLevel: 12,
    leadTeacherId: null,
    leadTeacherName: null,
  ),
];

Future<FakeExaminationRepository> pump(
  WidgetTester tester, {
  required FakeExaminationRepository fake,
  UserRole role = UserRole.schoolAdmin,
  String start = '/examinations',
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/examinations',
        builder: (context, state) => const Scaffold(body: ExaminationListScreen()),
      ),
      GoRoute(
        path: '/examinations/:id',
        builder: (context, state) =>
            Scaffold(body: ExaminationDetailScreen(examId: int.parse(state.pathParameters['id']!))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        examinationRepositoryProvider.overrideWithValue(fake),
        admitCardSaverProvider.overrideWithValue((name, bytes) => fake.saved.add(name)),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
        schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: classes)),
        subjectRepositoryProvider.overrideWithValue(FakeSubjectRepository(subjects: subjects)),
        ...viewedYearIs(year),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('the list', () {
    testWidgets('says what to do when the year has no exam, and offers a new one to an admin', (tester) async {
      await pump(tester, fake: FakeExaminationRepository());

      expect(find.byKey(const Key('exams-empty')), findsOneWidget);
      expect(find.byKey(const Key('exam-new')), findsOneWidget);
    });

    testWidgets('a teacher reads the exams but cannot create one', (tester) async {
      await pump(
        tester,
        fake: FakeExaminationRepository(exams: [exam()]),
        role: UserRole.teacher,
      );

      expect(find.text('Half-Yearly Examination'), findsOneWidget);
      expect(find.byKey(const Key('exam-new')), findsNothing);
    });

    testWidgets('each exam says whether it is a draft, published or changed since', (tester) async {
      await pump(
        tester,
        fake: FakeExaminationRepository(
          exams: [
            exam(id: 1),
            exam(id: 2, version: 1, papers: const [englishPaper]),
            exam(id: 3, version: 2, changes: true, papers: const [englishPaper]),
          ],
        ),
      );

      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Published · version 1'), findsOneWidget);
      expect(find.text('Version 2 · changes not published'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      await pump(tester, fake: FakeExaminationRepository(failWith: {'list': Failure.network()}));

      expect(find.text(Failure.network().message), findsOneWidget);
    });

    testWidgets('creating asks for a name, then sends the year in view and opens the new exam', (tester) async {
      final fake = await pump(tester, fake: FakeExaminationRepository());

      await tester.tap(find.byKey(const Key('exam-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exam-save')));
      await tester.pumpAndSettle();
      expect(find.text('Name the exam.'), findsOneWidget);
      expect(fake.calls, isNot(contains('create')));

      await tester.enterText(find.byKey(const Key('exam-name')), 'Half-Yearly Examination');
      await tester.tap(find.byKey(const Key('exam-save')));
      await tester.pumpAndSettle();

      expect(fake.lastFields!['academic_year_id'], 1);
      expect(fake.lastFields!['name'], 'Half-Yearly Examination');
      expect(find.byKey(const Key('exam-status')), findsOneWidget);
    });

    testWidgets("the server's refusal of a name lands on the field", (tester) async {
      await pump(
        tester,
        fake: FakeExaminationRepository(
          failWith: {
            'create': const Failure(
              code: 'VALIDATION_ERROR',
              message: 'This year already has an exam with this name.',
              details: {
                'errors': {
                  'name': ['This year already has an exam with this name.'],
                },
              },
            ),
          },
        ),
      );

      await tester.tap(find.byKey(const Key('exam-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exam-name')), 'Half-Yearly');
      await tester.tap(find.byKey(const Key('exam-save')));
      await tester.pumpAndSettle();

      expect(find.text('This year already has an exam with this name.'), findsOneWidget);
    });
  });

  group('the date sheet', () {
    testWidgets('a draft with no papers cannot be published and says to add one', (tester) async {
      await pump(
        tester,
        fake: FakeExaminationRepository(exams: [exam()]),
        start: '/examinations/7',
      );

      expect(find.byKey(const Key('sheet-empty')), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('exam-publish'))).onPressed, isNull);
    });

    testWidgets('a row needs a class, subject and date before anything is sent', (tester) async {
      final fake = await pump(
        tester,
        fake: FakeExaminationRepository(exams: [exam()]),
        start: '/examinations/7',
      );

      await tester.tap(find.byKey(const Key('sheet-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet-save')));
      await tester.pumpAndSettle();

      expect(find.text('Row 1 needs a class, a subject and a date.'), findsOneWidget);
      expect(fake.calls, isNot(contains('savePapers')));
    });

    testWidgets('an existing sheet saves back whole after an edit', (tester) async {
      final fake = await pump(
        tester,
        fake: FakeExaminationRepository(
          exams: [
            exam(papers: const [englishPaper]),
          ],
        ),
        start: '/examinations/7',
      );

      await tester.tap(find.byKey(const Key('sheet-remove-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet-save')));
      await tester.pumpAndSettle();

      expect(fake.lastPapers, isEmpty);
      expect(find.text('Date sheet saved.'), findsOneWidget);
    });

    testWidgets("the server's sentence about a clash lands on that row", (tester) async {
      await pump(
        tester,
        fake: FakeExaminationRepository(
          exams: [
            exam(papers: const [englishPaper]),
          ],
          failWith: {
            'savePapers': const Failure(
              code: 'VALIDATION_ERROR',
              message: 'This overlaps English for Class 8 on the same day.',
              details: {
                'errors': {
                  'papers.0.start_time': ['This overlaps English for Class 8 on the same day.'],
                },
              },
            ),
          },
        ),
        start: '/examinations/7',
      );

      await tester.tap(find.byKey(const Key('sheet-start-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet-save')));
      await tester.pumpAndSettle();

      expect(find.text('This overlaps English for Class 8 on the same day.'), findsWidgets);
    });

    testWidgets('a teacher reads the sheet with nothing to edit', (tester) async {
      await pump(
        tester,
        fake: FakeExaminationRepository(
          exams: [
            exam(version: 1, papers: const [englishPaper]),
          ],
        ),
        role: UserRole.teacher,
        start: '/examinations/7',
      );

      expect(find.byKey(const Key('sheet-add')), findsNothing);
      expect(find.byKey(const Key('exam-publish')), findsNothing);
    });
  });

  group('publishing', () {
    testWidgets('asks first, then publishes version 1', (tester) async {
      final fake = await pump(
        tester,
        fake: FakeExaminationRepository(
          exams: [
            exam(papers: const [englishPaper]),
          ],
        ),
        start: '/examinations/7',
      );

      await tester.tap(find.byKey(const Key('exam-publish')));
      await tester.pumpAndSettle();
      expect(find.text('Publish the admit cards?'), findsOneWidget);

      await tester.tap(find.text('Publish').last);
      await tester.pumpAndSettle();

      expect(fake.calls, contains('publish'));
      expect(find.text('Published as version 1.'), findsOneWidget);
      expect(find.text('Published · version 1'), findsOneWidget);
    });

    testWidgets('a change after publishing says cards still print the old version', (tester) async {
      await pump(
        tester,
        fake: FakeExaminationRepository(
          exams: [
            exam(version: 1, changes: true, papers: const [englishPaper]),
          ],
        ),
        start: '/examinations/7',
      );

      expect(find.byKey(const Key('exam-unpublished-note')), findsOneWidget);
      expect(find.text('Publish version 2'), findsOneWidget);
    });

    testWidgets('a refusal from the server is said, not swallowed', (tester) async {
      await pump(
        tester,
        fake: FakeExaminationRepository(
          exams: [
            exam(papers: const [englishPaper]),
          ],
          failWith: {
            'publish': const Failure(code: 'EXAMINATION_NOT_READY', message: 'Nothing has changed since version 1.'),
          },
        ),
        start: '/examinations/7',
      );

      await tester.tap(find.byKey(const Key('exam-publish')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish').last);
      await tester.pumpAndSettle();

      expect(find.text('Nothing has changed since version 1.'), findsOneWidget);
    });
  });

  group('the admit cards', () {
    Future<FakeExaminationRepository> openCards(WidgetTester tester, {int version = 1, UserRole? role}) async {
      final fake = await pump(
        tester,
        fake: FakeExaminationRepository(
          exams: [
            exam(version: version, papers: const [englishPaper]),
          ],
          candidateRows: [
            candidate(1, 'Aarav Kumar', version == 0 ? CardState.notPublished : CardState.ready),
            candidate(
              2,
              'Kabir Singh',
              version == 0 ? CardState.notPublished : CardState.withheld,
              reason: 'Disciplinary',
              exception: 'withhold',
            ),
          ],
        ),
        role: role ?? UserRole.schoolAdmin,
        start: '/examinations/7',
      );
      await tester.tap(find.byKey(const Key('exam-tab-cards')));
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('lists each student with the state of their card, and staff read the reason', (tester) async {
      await openCards(tester);

      expect(find.text('Aarav Kumar'), findsOneWidget);
      expect(find.text('Withheld'), findsOneWidget);
      expect(find.textContaining('Reason: Disciplinary'), findsOneWidget);
      expect(find.byKey(const Key('cards-state-ready')), findsOneWidget);
    });

    testWidgets('a ready card downloads, a withheld one offers no download', (tester) async {
      final fake = await openCards(tester);

      expect(find.byKey(const Key('candidate-card-2')), findsNothing);
      await tester.tap(find.byKey(const Key('candidate-card-1')));
      await tester.pumpAndSettle();

      expect(fake.lastCard, (studentId: 1, draft: false));
      expect(fake.saved, ['admit-card-ADM-1.pdf']);
    });

    testWidgets('a draft card can be previewed by the manager before publishing', (tester) async {
      final fake = await openCards(tester, version: 0);

      expect(find.byKey(const Key('cards-not-published')), findsOneWidget);
      await tester.tap(find.byKey(const Key('candidate-draft-1')));
      await tester.pumpAndSettle();

      expect(fake.lastCard, (studentId: 1, draft: true));
    });

    testWidgets('printing a section waits for one to be chosen, then says how many were left out', (tester) async {
      final fake = await openCards(tester);

      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('cards-print-section'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('cards-section')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class 8 - A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cards-print-section')));
      await tester.pumpAndSettle();

      expect(fake.lastSection, 81);
      expect(find.textContaining('2 cards ready to print. 1 left out'), findsOneWidget);
    });

    testWidgets('withholding asks for the reason, which is required', (tester) async {
      final fake = await openCards(tester);

      await tester.tap(find.byKey(const Key('candidate-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Withhold card'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cards-reason-save')));
      await tester.pumpAndSettle();
      expect(find.text('Say why the card is withheld.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('cards-reason')), 'Uniform not returned');
      await tester.tap(find.byKey(const Key('cards-reason-save')));
      await tester.pumpAndSettle();

      expect(fake.lastException, (studentId: 1, kind: 'withhold', reason: 'Uniform not returned'));
      expect(find.text("Aarav Kumar's card is withheld."), findsOneWidget);
    });

    testWidgets('a withheld card can go back to the rules', (tester) async {
      final fake = await openCards(tester);

      await tester.tap(find.byKey(const Key('candidate-menu-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Back to the exam's rules"));
      await tester.pumpAndSettle();

      expect(fake.lastException, (studentId: 2, kind: null, reason: null));
    });

    testWidgets('a teacher may download but not hold a card', (tester) async {
      await openCards(tester, role: UserRole.teacher);

      expect(find.byKey(const Key('candidate-card-1')), findsOneWidget);
      expect(find.byKey(const Key('candidate-menu-1')), findsNothing);
    });

    testWidgets('a failed download says the server\'s reason', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      final fake = FakeExaminationRepository(
        exams: [
          exam(version: 1, papers: const [englishPaper]),
        ],
        candidateRows: [candidate(1, 'Aarav Kumar', CardState.ready)],
        failWith: {'card': const Failure(code: 'ADMIT_CARD_UNAVAILABLE', message: 'Held: fees overdue.')},
      );
      await pump(tester, fake: fake, start: '/examinations/7');
      await tester.tap(find.byKey(const Key('exam-tab-cards')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('candidate-card-1')));
      await tester.pumpAndSettle();

      expect(find.text('Held: fees overdue.'), findsOneWidget);
    });
  });
}
