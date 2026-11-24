import 'package:edutrack_app/core/utils/calendar_file.dart';
import 'package:edutrack_app/features/family/data/models/family_admit_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart' show pumpFamilyApp;

/// "Add to calendar" (docs/mobile-apps-review.md, M8, 6.3): the exam date
/// sheet and the school's holidays as a calendar file for the phone.
void main() {
  group('the calendar file', () {
    test('a timed paper keeps the school time, with no zone', () {
      final file = calendarFile(
        [
          CalendarItem.timed(
            uid: 'exam-1',
            title: 'English - Half-Yearly',
            day: DateTime(2026, 12, 7),
            start: '9:00',
            end: '12:00',
            location: 'Main Campus',
          ),
        ],
        name: 'Half-Yearly',
        now: DateTime.utc(2026, 11, 24, 10),
      );

      expect(file, contains('DTSTART:20261207T090000\r\n'));
      expect(file, contains('DTEND:20261207T120000\r\n'));
      expect(file, contains('SUMMARY:English - Half-Yearly\r\n'));
      expect(file, contains('LOCATION:Main Campus\r\n'));
      expect(file, contains('UID:exam-1@school365ai.com\r\n'));
      expect(file, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(file, endsWith('END:VCALENDAR\r\n'));
    });

    test('a holiday lasts whole days and ends the day after its last day', () {
      final file = calendarFile([
        CalendarItem.allDay(
          uid: 'h',
          title: 'Diwali break',
          day: DateTime(2026, 11, 9),
          lastDay: DateTime(2026, 11, 11),
        ),
      ], name: 'Holidays');

      expect(file, contains('DTSTART;VALUE=DATE:20261109\r\n'));
      expect(file, contains('DTEND;VALUE=DATE:20261112\r\n'));
    });

    test('commas and semicolons are escaped, and a long line is folded', () {
      final file = calendarFile([
        CalendarItem.allDay(uid: 'x', title: 'Sports day, prize giving; parents welcome', day: DateTime(2026, 12, 1)),
        CalendarItem.allDay(uid: 'y', title: 'A' * 120, day: DateTime(2026, 12, 2)),
      ], name: 'Test');

      expect(file, contains(r'SUMMARY:Sports day\, prize giving\; parents welcome'));
      final summary = file.split('\r\n').firstWhere((line) => line.startsWith('SUMMARY:AAAA'));
      expect(summary.length, lessThanOrEqualTo(75));
      expect(file, contains('\r\n A'));
    });
  });

  group('in the Family app', () {
    final halfYearly = FamilyAdmitCard(
      examinationId: 7,
      name: 'Half-Yearly Examination',
      yearName: '2026-27',
      available: true,
      state: 'ready',
      message: 'Ready to download',
      version: 1,
      issuedOn: '11/17/2026',
      reportingTime: '08:30',
      centre: 'Main Campus',
      papers: [
        ExamPaper(subject: 'English', date: DateTime(2026, 12, 7), start: '09:00', end: '12:00'),
        ExamPaper(subject: 'Mathematics', date: DateTime(2026, 12, 9), start: '09:00', end: '12:00'),
      ],
    );

    testWidgets("an exam's papers go to the phone's calendar as one file", (tester) async {
      final shared = <(String, String)>[];
      final data = FakeFamilyRepository()..admitCardList = [halfYearly];
      await pumpFamilyApp(
        tester,
        data: data,
        goTo: '/admit-cards',
        onCalendar: (contents, name) async => shared.add((contents, name)),
      );

      await tester.tap(find.byKey(const Key('family-exam-calendar-7')));
      await tester.pumpAndSettle();

      final (contents, name) = shared.single;
      expect(name, 'half-yearly-examination.ics');
      expect('BEGIN:VEVENT'.allMatches(contents).length, 2);
      expect(contents, contains('SUMMARY:English - Half-Yearly Examination'));
      expect(contents, contains('DESCRIPTION:Reporting time 08:30.'));
    });

    testWidgets('an exam with no papers for the class offers nothing', (tester) async {
      final data = FakeFamilyRepository()
        ..admitCardList = const [
          FamilyAdmitCard(
            examinationId: 8,
            name: 'Unit Test',
            yearName: '2026-27',
            available: false,
            state: 'held',
            message: 'Contact the school',
          ),
        ];
      await pumpFamilyApp(tester, data: data, goTo: '/admit-cards');

      expect(find.byKey(const Key('family-exam-calendar-8')), findsNothing);
    });

    testWidgets("the coming holidays go to the phone's calendar", (tester) async {
      final shared = <(String, String)>[];
      await pumpFamilyApp(
        tester,
        goTo: '/calendar',
        onCalendar: (contents, name) async => shared.add((contents, name)),
      );

      await tester.scrollUntilVisible(find.byKey(const Key('family-holidays-calendar')), 200);
      await tester.tap(find.byKey(const Key('family-holidays-calendar')));
      await tester.pumpAndSettle();

      final (contents, name) = shared.single;
      expect(name, 'school-holidays.ics');
      expect(contents, contains('SUMMARY:Guru Nanak Jayanti'));
      expect(contents, contains('DTSTART;VALUE=DATE:20261124'));
    });
  });
}
