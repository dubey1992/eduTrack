import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/family/data/models/family_learning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart' show pumpFamilyApp;

/// A child's learning in the Family app (docs/parent-student-app.md, F2).
void main() {
  group('Results', () {
    testWidgets('shows each subject with the mark, the grade and the teacher\'s remark', (tester) async {
      await pumpFamilyApp(tester, goTo: '/results');

      expect(find.text('Aarav works hard and helps others.'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('Grade A'), findsOneWidget);

      await tester.tap(find.text('Mathematics'));
      await tester.pumpAndSettle();

      expect(find.text('18 / 20'), findsOneWidget);
      // Absent is said, never shown as nought.
      expect(find.text('Absent'), findsOneWidget);
    });

    testWidgets('no class average unless the school shows it', (tester) async {
      await pumpFamilyApp(tester, goTo: '/results');
      await tester.tap(find.text('Mathematics'));
      await tester.pumpAndSettle();

      expect(find.textContaining('class average'), findsNothing);
    });

    testWidgets('the class average when the school shows it', (tester) async {
      final data = FakeFamilyRepository()..resultsFor = (_) => familyResults(showsAverage: true);
      await pumpFamilyApp(tester, data: data, goTo: '/results');
      await tester.tap(find.text('Mathematics'));
      await tester.pumpAndSettle();

      expect(find.text('10/20/2026 · class average 70%'), findsOneWidget);
    });

    testWidgets('choosing another term asks for it', (tester) async {
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/results');

      await tester.tap(find.byKey(const Key('family-term-1')));
      await tester.pumpAndSettle();

      expect(data.resultsAskedFor, [null, 1]);
    });

    testWidgets('the progress report waits for the end of the term', (tester) async {
      await pumpFamilyApp(tester, goTo: '/results');

      expect(find.text('Ready when the term ends, on 02/01/2027.'), findsOneWidget);
      expect(find.byKey(const Key('family-download-report')), findsNothing);
    });

    testWidgets('a finished term\'s report is handed to the phone', (tester) async {
      final handed = <String>[];
      final (data, _, _) = await pumpFamilyApp(
        tester,
        goTo: '/results',
        onPdf: (bytes, name) async => handed.add(name),
      );

      await tester.tap(find.byKey(const Key('family-term-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-download-report')));
      await tester.pumpAndSettle();

      expect(data.reportsAskedFor, [1]);
      expect(handed, ['progress-report-aarav-term-1.pdf']);
    });

    testWidgets('a report the school refuses says why', (tester) async {
      final data = FakeFamilyRepository()
        ..failReportWith = const Failure(code: 'PROGRESS_REPORT_NOT_READY', message: 'Not ready yet.');
      await pumpFamilyApp(tester, data: data, goTo: '/results');

      await tester.tap(find.byKey(const Key('family-term-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-download-report')));
      await tester.pumpAndSettle();

      expect(find.text('Not ready yet.'), findsOneWidget);
    });
  });

  group('Timetable', () {
    testWidgets('opens on today, periods and breaks in bell order', (tester) async {
      await pumpFamilyApp(tester, goTo: '/timetable');

      expect(find.text('Mon · today'), findsOneWidget);
      final maths = tester.getTopLeft(find.text('Mathematics')).dy;
      final pause = tester.getTopLeft(find.text('Short break')).dy;
      final science = tester.getTopLeft(find.text('Science')).dy;
      expect(maths < pause && pause < science, isTrue);
    });

    testWidgets('another day, and a half day says so', (tester) async {
      await pumpFamilyApp(tester, goTo: '/timetable');

      await tester.tap(find.byKey(const Key('family-day-saturday')));
      await tester.pumpAndSettle();

      expect(find.text('Saturday is a half day.'), findsOneWidget);
      expect(find.text('Art'), findsOneWidget);
    });
  });

  group('Syllabus', () {
    testWidgets('says how far each subject has got and what comes next', (tester) async {
      await pumpFamilyApp(tester, goTo: '/syllabus');

      expect(find.text('14 of 22 topics covered'), findsOneWidget);
      expect(find.text('64%'), findsOneWidget);
      expect(find.text('Coming up: Light, Sound'), findsOneWidget);
    });
  });

  test('marks read the way a person writes them', () {
    expect(readableNumber('18.00'), '18');
    expect(readableNumber('17.50'), '17.5');
    expect(readableNumber(null), '-');
  });

  testWidgets('More leads to the three learning screens', (tester) async {
    await pumpFamilyApp(tester, goTo: '/more');

    for (final key in ['family-more-results', 'family-more-timetable', 'family-more-syllabus']) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
  });
}
