import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/absence_notes/data/absence_notes.dart';
import 'package:edutrack_app/features/absence_notes/presentation/absence_note_chip.dart';
import 'package:edutrack_app/features/absence_notes/presentation/absence_notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parents' absence notes as the school sees them (docs/parent-student-app.md,
/// F5): the list, opening a note, and marking it as seen.
class FakeAbsenceNotesRepository implements AbsenceNotesRepository {
  FakeAbsenceNotesRepository({this.failListWith, this.failAcknowledgeWith});

  Failure? failListWith;
  Failure? failAcknowledgeWith;
  final List<bool?> listedWith = [];
  final List<int> acknowledged = [];

  static StaffAbsenceNote note({int id = 1, bool seen = false, bool photo = false}) => StaffAbsenceNote(
    id: id,
    studentId: 11,
    studentName: 'Aarav Sharma',
    startDate: DateTime(2026, 11, 9),
    endDate: DateTime(2026, 11, 10),
    reason: 'Fever - the doctor advised two days of rest.',
    hasPhoto: photo,
    acknowledged: seen,
    sentBy: 'Meera Sharma',
    acknowledgedBy: seen ? 'Neha Iyer' : null,
  );

  @override
  Future<PaginatedResponse<StaffAbsenceNote>> list({bool? unseenOnly, int page = 1}) async {
    listedWith.add(unseenOnly);
    if (failListWith != null) throw failListWith!;
    final items = unseenOnly == false ? [note(id: 2, seen: true)] : [note()];
    return PaginatedResponse(items: items, currentPage: 1, lastPage: 1, total: items.length, perPage: 20);
  }

  @override
  Future<StaffAbsenceNote> acknowledge(int noteId) async {
    if (failAcknowledgeWith != null) throw failAcknowledgeWith!;
    acknowledged.add(noteId);
    return note(id: noteId, seen: true);
  }

  @override
  Future<List<int>> photo(int noteId) async => const [];
}

Future<FakeAbsenceNotesRepository> pumpScreen(WidgetTester tester, {FakeAbsenceNotesRepository? fake}) async {
  final repository = fake ?? FakeAbsenceNotesRepository();
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [absenceNotesRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: AbsenceNotesScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('opens on the notes nobody has seen yet', (tester) async {
    final fake = await pumpScreen(tester);

    expect(fake.listedWith, [true]);
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.textContaining('From Meera Sharma'), findsOneWidget);
  });

  testWidgets('"Seen" lists the notes already marked, and by whom', (tester) async {
    final fake = await pumpScreen(tester);

    await tester.tap(find.text('Seen'));
    await tester.pumpAndSettle();

    expect(fake.listedWith.last, false);
    expect(find.textContaining('seen by Neha Iyer'), findsOneWidget);
  });

  testWidgets('opening a note and marking it as seen tells the server and says so', (tester) async {
    final fake = await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('absence-note-open-1')));
    await tester.pumpAndSettle();
    expect(find.text('Note about Aarav Sharma'), findsOneWidget);
    expect(find.textContaining('doesn\'t mark the register'), findsOneWidget);

    await tester.tap(find.byKey(const Key('absence-note-acknowledge')));
    await tester.pumpAndSettle();

    expect(fake.acknowledged, [1]);
    expect(find.textContaining('Marked as seen'), findsOneWidget);
  });

  testWidgets('a refusal keeps the dialog open with the reason', (tester) async {
    final fake = FakeAbsenceNotesRepository(
      failAcknowledgeWith: const Failure(code: 'FORBIDDEN', message: 'You do not keep this register.'),
    );
    await pumpScreen(tester, fake: fake);

    await tester.tap(find.byKey(const Key('absence-note-open-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('absence-note-acknowledge')));
    await tester.pumpAndSettle();

    expect(find.text('You do not keep this register.'), findsOneWidget);
    expect(find.text('Note about Aarav Sharma'), findsOneWidget);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    final fake = FakeAbsenceNotesRepository(failListWith: Failure.network());
    await pumpScreen(tester, fake: fake);
    expect(find.text(Failure.network().message), findsOneWidget);

    fake.failListWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Aarav Sharma'), findsOneWidget);
  });

  testWidgets('the register chip says whether the note has been seen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [absenceNotesRepositoryProvider.overrideWithValue(FakeAbsenceNotesRepository())],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Column(
              children: [
                AbsenceNoteChip(
                  note: RegisterAbsenceNote(id: 1, reason: 'Fever.', acknowledged: false, hasPhoto: false),
                  studentName: 'Aarav',
                ),
                AbsenceNoteChip(
                  note: RegisterAbsenceNote(id: 2, reason: 'Wedding.', acknowledged: true, hasPhoto: false),
                  studentName: 'Diya',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Parent\'s note'), findsOneWidget);
    expect(find.text('Parent\'s note · seen'), findsOneWidget);

    await tester.tap(find.text('Parent\'s note · seen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('absence-note-acknowledge')), findsNothing, reason: 'already seen');
  });
}
