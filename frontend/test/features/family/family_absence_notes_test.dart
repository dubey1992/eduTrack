import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart';

/// Absence notes in the Family app (docs/parent-student-app.md, F5): telling
/// the school a child will be away, and seeing that the class teacher has.
void main() {
  group('the notes sent', () {
    testWidgets('each says sent, or seen by the class teacher', (tester) async {
      await pumpFamilyApp(tester, goTo: '/absence-notes');

      expect(
        find.descendant(of: find.byKey(const Key('family-note-7')), matching: find.text('Seen by the class teacher')),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byKey(const Key('family-note-8')), matching: find.text('Sent')), findsOneWidget);
      expect(find.text('With a photo of a note'), findsOneWidget);
    });

    testWidgets('none sent says how', (tester) async {
      final data = FakeFamilyRepository()..notesValue = [];
      await pumpFamilyApp(tester, data: data, goTo: '/absence-notes');

      expect(find.text('No notes sent'), findsOneWidget);
    });

    testWidgets('a failure says so and tries again', (tester) async {
      final data = FakeFamilyRepository()..failNotesWith = Failure.network();
      await pumpFamilyApp(tester, data: data, goTo: '/absence-notes');
      expect(find.text('No connection'), findsOneWidget);

      data.failNotesWith = null;
      await tester.tap(find.byKey(const Key('family-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('family-note-8')), findsOneWidget);
    });

    testWidgets('the Attendance tab is the way in', (tester) async {
      await pumpFamilyApp(tester, goTo: '/attendance');

      await tester.tap(find.byKey(const Key('family-tell-absence')));
      await tester.pumpAndSettle();

      expect(find.text('Aarav will be away'), findsOneWidget);
    });
  });

  group('telling the school', () {
    Future<void> writeReason(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('family-note-reason')), text);
      await tester.pump();
    }

    Future<void> sendNote(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('family-note-send')));
      await tester.tap(find.byKey(const Key('family-note-send')));
      await tester.pumpAndSettle();
    }

    testWidgets('a reason too short is asked for again, and nothing is sent', (tester) async {
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/absence-notes/new');

      await writeReason(tester, 'sick');
      await sendNote(tester);

      expect(find.textContaining('at least 10 characters'), findsOneWidget);
      expect(data.notesSent, isEmpty);
    });

    testWidgets('a note for today is sent, the parent goes back and is told', (tester) async {
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/absence-notes');
      await tester.tap(find.byKey(const Key('family-new-note')));
      await tester.pumpAndSettle();

      await writeReason(tester, 'Fever since last night - resting at home today.');
      await sendNote(tester);

      expect(data.notesSent.single.start, DateTime(2026, 11, 9));
      expect(data.notesSent.single.end, DateTime(2026, 11, 9));
      expect(find.textContaining('class teacher will see it'), findsOneWidget);
      expect(find.byKey(const Key('family-new-note')), findsOneWidget, reason: 'back on the list');
    });

    testWidgets('a photo of the doctor\'s note goes with it', (tester) async {
      final (data, _, _) = await pumpFamilyApp(
        tester,
        goTo: '/absence-notes/new',
        onPickPhoto: (source) async => const PickedFile(name: 'doctor.jpg', bytes: [1, 2, 3]),
      );

      await tester.tap(find.byKey(const Key('family-note-add-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-photo-gallery')));
      await tester.pumpAndSettle();
      expect(find.text('doctor.jpg'), findsOneWidget);

      await writeReason(tester, 'Chickenpox - the doctor\'s note is attached.');
      await sendNote(tester);

      expect(data.notesSent.single.photoName, 'doctor.jpg');
    });

    testWidgets('a photo can be taken away again before sending', (tester) async {
      await pumpFamilyApp(
        tester,
        goTo: '/absence-notes/new',
        onPickPhoto: (source) async => const PickedFile(name: 'doctor.jpg', bytes: [1, 2, 3]),
      );
      await tester.tap(find.byKey(const Key('family-note-add-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-photo-camera')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('family-note-remove-photo')));
      await tester.pumpAndSettle();

      expect(find.text('doctor.jpg'), findsNothing);
    });

    testWidgets('days already covered show the school\'s answer, not a second note', (tester) async {
      final data = FakeFamilyRepository()
        ..failSendWith = const Failure(
          code: 'ABSENCE_NOTE_ALREADY_SENT',
          message: 'You already told the school about from Mon Nov 9 to Tue Nov 10.',
        );
      await pumpFamilyApp(tester, data: data, goTo: '/absence-notes/new');

      await writeReason(tester, 'Still unwell, staying at home.');
      await sendNote(tester);

      expect(find.byKey(const Key('family-note-problem')), findsOneWidget);
      expect(find.textContaining('You already told the school'), findsOneWidget);
    });

    testWidgets('a day the school refuses is explained under that day', (tester) async {
      final data = FakeFamilyRepository()
        ..failSendWith = const Failure(
          code: 'ABSENCE_NOTE_REFUSED',
          message: 'The school is closed on all of those days, so there is nothing to tell it.',
          details: {
            'errors': {
              'start_date': ['The school is closed on all of those days.'],
            },
          },
        );
      await pumpFamilyApp(tester, data: data, goTo: '/absence-notes/new');

      await writeReason(tester, 'Family function out of town.');
      await sendNote(tester);

      expect(find.text('The school is closed on all of those days.'), findsOneWidget);
    });
  });
}
