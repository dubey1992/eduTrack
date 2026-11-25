import 'package:edutrack_app/features/assessments/data/models/assessment_sheet.dart';
import 'package:edutrack_app/features/my_teaching/application/marks_reading.dart';
import 'package:flutter_test/flutter_test.dart';

/// Marks read from voice or a photo (docs/mobile-apps-review.md, M12, 1.7).
void main() {
  SheetEntry student(int id, {String? roll, String? marks, bool absent = false}) => SheetEntry(
    studentId: id,
    studentName: 'Student $id',
    admissionNumber: 'ADM-$id',
    rollNumber: roll ?? '$id',
    marksObtained: marks,
    isAbsent: absent,
    grade: null,
    percentage: null,
    passed: null,
    remarks: null,
  );

  // Rolls 1..5, students 101..105.
  final sheet = [for (var roll = 1; roll <= 5; roll++) student(100 + roll, roll: '$roll')];
  final parser = MarksParser(sheet);

  Map<int, String> marks(MarksReading reading) => {
    for (final entry in reading.byStudent.entries) entry.key: entry.value.toString(),
  };

  ReadLine line(String text, double top, {double left = 0, double height = 20}) =>
      ReadLine(text: text, top: top, bottom: top + height, left: left);

  group('speech: roll and mark', () {
    test('"roll 2 45" gives roll 2 a 45', () {
      expect(marks(parser.fromSpeech('roll 2 45')), {102: '45'});
    });

    test('"roll 2, 45" with a comma', () {
      expect(marks(parser.fromSpeech('Roll 2, 45')), {102: '45'});
    });

    test('several rolls in one go', () {
      expect(marks(parser.fromSpeech('roll 1 18 roll 3 12.5 roll 5 20')), {101: '18', 103: '12.5', 105: '20'});
    });

    test('"roll number", "roll no." and "role" as it is often heard', () {
      expect(marks(parser.fromSpeech('roll number 1 10 roll no. 2 11 role 3 12')), {101: '10', 102: '11', 103: '12'});
    });

    test('"roll 4 absent" marks roll 4 absent', () {
      expect(parser.fromSpeech('roll 4 absent').byStudent, {104: const ReadMark.absent()});
    });

    test('"12 45" alone is a roll and a mark when 12 is a roll', () {
      expect(marks(parser.fromSpeech('3 17')), {103: '17'});
    });

    test('two numbers whose first is no roll are two marks in order', () {
      expect(marks(parser.fromSpeech('15 18')), {101: '15', 102: '18'});
    });

    test('comma-separated pairs', () {
      expect(marks(parser.fromSpeech('1 10, 4 14')), {101: '10', 104: '14'});
    });

    test('a roll not on the sheet is reported, with its mark', () {
      final reading = parser.fromSpeech('roll 9 45');
      expect(reading.byStudent, isEmpty);
      expect(reading.issues, [const ReadIssue(ReadIssueKind.unknownRoll, roll: '9', value: ReadMark.mark('45'))]);
    });

    test('a roll with no mark after it is flagged on that student', () {
      expect(parser.fromSpeech('roll 2').byStudent, {102: const ReadMark.unreadable('')});
    });

    test('the same roll twice keeps the last and says so', () {
      final reading = parser.fromSpeech('roll 2 10 roll 2 12');
      expect(marks(reading), {102: '12'});
      expect(reading.issues, [const ReadIssue(ReadIssueKind.readTwice, roll: '2', value: ReadMark.mark('10'))]);
    });

    test('numbers after a roll and its mark are extra', () {
      final reading = parser.fromSpeech('roll 2 10 11');
      expect(marks(reading), {102: '10'});
      expect(reading.issues, [const ReadIssue(ReadIssueKind.extraValue, value: ReadMark.mark('11'))]);
    });

    test('a roll written with a leading zero on the sheet', () {
      final padded = MarksParser([student(1, roll: '07')]);
      expect(marks(padded.fromSpeech('roll 7 9')), {1: '9'});
    });
  });

  group('speech: marks in roll order', () {
    test('a run of marks fills the sheet from the top', () {
      expect(marks(parser.fromSpeech('12 15 18')), {101: '12', 102: '15', 103: '18'});
    });

    test('from where the teacher left off', () {
      expect(marks(parser.fromSpeech('12 15', startAt: 3)), {104: '12', 105: '15'});
    });

    test('absent in a run takes its place', () {
      expect(parser.fromSpeech('12 absent 18').byStudent, {
        101: const ReadMark.mark('12'),
        102: const ReadMark.absent(),
        103: const ReadMark.mark('18'),
      });
    });

    test('more marks than students: the rest are reported, not dropped silently', () {
      final reading = parser.fromSpeech('1 2 3 4 5 6 7', startAt: 0);
      expect(reading.byStudent.length, 5);
      expect(reading.issues, [
        const ReadIssue(ReadIssueKind.extraValue, value: ReadMark.mark('6')),
        const ReadIssue(ReadIssueKind.extraValue, value: ReadMark.mark('7')),
      ]);
    });

    test('a run fills round a student named by roll', () {
      expect(marks(parser.fromSpeech('11 12 roll 1 20')), {101: '20', 102: '11', 103: '12'});
    });

    test('firstUnmarked is the first student with neither mark nor absence', () {
      expect(MarksParser.firstUnmarked([student(1, marks: '4'), student(2, absent: true), student(3)]), 2);
      expect(MarksParser.firstUnmarked([student(1, marks: '4')]), 0, reason: 'all marked: from the top');
      expect(MarksParser.firstUnmarked(const []), 0);
    });
  });

  group('speech: numbers in words', () {
    test('forty five, forty-five', () {
      expect(marks(parser.fromSpeech('forty five forty-five')), {101: '45', 102: '45'});
    });

    test('teens, tens and zero', () {
      expect(marks(parser.fromSpeech('twelve twenty zero nineteen')), {101: '12', 102: '20', 103: '0', 104: '19'});
    });

    test('halves: point five, 45.5, and a half', () {
      expect(marks(parser.fromSpeech('45 point 5, forty five point five, 45.5, 45 and a half, nine and half')), {
        101: '45.5',
        102: '45.5',
        103: '45.5',
        104: '45.5',
        105: '9.5',
      });
    });

    test('one hundred, a hundred, one hundred and five', () {
      final big = MarksParser([student(1), student(2), student(3)]);
      expect(marks(big.fromSpeech('one hundred a hundred one hundred and five')), {1: '100', 2: '100', 3: '105'});
    });

    test('roll in words too', () {
      expect(marks(parser.fromSpeech('roll three seventeen')), {103: '17'});
    });

    test('"45 out of 50" is a 45', () {
      expect(marks(parser.fromSpeech('roll 1 45 out of 50')), {101: '45'});
    });

    test('Devanagari digits, as a phone set to Hindi may write them', () {
      expect(marks(parser.fromSpeech('रोल roll २ ४५')), {102: '45'});
    });
  });

  group('speech: nothing useful', () {
    test('empty', () {
      expect(parser.fromSpeech('').isEmpty, isTrue);
      expect(parser.fromSpeech('   ').isEmpty, isTrue);
    });

    test('words with no numbers', () {
      expect(parser.fromSpeech('hello is this thing on').isEmpty, isTrue);
    });

    test('a sheet with no students', () {
      final reading = MarksParser(const []).fromSpeech('12 14');
      expect(reading.byStudent, isEmpty);
      expect(reading.issues.map((issue) => issue.kind), [ReadIssueKind.extraValue, ReadIssueKind.extraValue]);
    });

    test('over the maximum is read as said: the review step flags it', () {
      expect(marks(parser.fromSpeech('roll 1 85')), {101: '85'});
    });
  });

  group('photo', () {
    test('rows of roll, name and mark, in any order of lines', () {
      final reading = parser.fromPhoto([
        line('3 Kabir Rao 12', 100),
        line('1 Aarav Shah 18', 20),
        line('2 Diya Patel 9.5', 60),
      ]);
      expect(marks(reading), {101: '18', 102: '9.5', 103: '12'});
    });

    test('a row ML Kit split into separate lines is put back together', () {
      final reading = parser.fromPhoto([
        line('Aarav Shah', 21, left: 60),
        line('18', 19, left: 300),
        line('1', 20, left: 10),
        line('Diya Patel', 60, left: 60),
        line('2', 61, left: 10),
        line('AB', 59, left: 300),
      ]);
      expect(reading.byStudent, {101: const ReadMark.mark('18'), 102: const ReadMark.absent()});
    });

    test('headers and the maximum line are skipped', () {
      final reading = parser.fromPhoto([
        line('Class 8A Mathematics', 0),
        line('Max marks 20', 30),
        line('Roll No. Name Marks', 60),
        line('1. Aarav 18', 90),
      ]);
      expect(marks(reading), {101: '18'});
      expect(reading.issues, isEmpty);
    });

    test('"18/20" is an 18', () {
      expect(marks(parser.fromPhoto([line('1 Aarav 18/20', 0)])), {101: '18'});
    });

    test('a marks column on its own fills in roll order', () {
      expect(marks(parser.fromPhoto([line('18', 0), line('14', 30), line('9', 60)])), {101: '18', 102: '14', 103: '9'});
    });

    test('names with marks but no rolls fill in order', () {
      expect(marks(parser.fromPhoto([line('Aarav Shah 18', 0), line('Diya Patel 14', 30)])), {101: '18', 102: '14'});
    });

    test('handwriting read as letters: 4S is 45, l7 is 17, O is 0', () {
      final reading = parser.fromPhoto([line('1 Aarav 4S', 0), line('2 Diya l7', 30), line('3 Kabir 1O', 60)]);
      expect(marks(reading), {101: '45', 102: '17', 103: '10'});
    });

    test('an unreadable mark is flagged on its student', () {
      final reading = parser.fromPhoto([line('2 Diya 4q', 0)]);
      expect(reading.byStudent, {102: const ReadMark.unreadable('4q')});
    });

    test('an unreadable mark in a marks column keeps its place', () {
      final reading = parser.fromPhoto([line('18', 0), line('7x', 30), line('9', 60)]);
      expect(reading.byStudent, {
        101: const ReadMark.mark('18'),
        102: const ReadMark.unreadable('7x'),
        103: const ReadMark.mark('9'),
      });
    });

    test('a roll that is nobody on the sheet', () {
      final reading = parser.fromPhoto([line('9 New Kid 11', 0)]);
      expect(reading.byStudent, isEmpty);
      expect(reading.issues, [const ReadIssue(ReadIssueKind.unknownRoll, roll: '9', value: ReadMark.mark('11'))]);
    });

    test('a roll photographed twice', () {
      final reading = parser.fromPhoto([line('1 Aarav 18', 0), line('1 Aarav 19', 30)]);
      expect(marks(reading), {101: '19'});
      expect(reading.issues.single.kind, ReadIssueKind.readTwice);
    });

    test('a row whose roll was misread lands on the student left over', () {
      // Roll 2's "2" was lost, so "Diya 14" has no roll: it fills the one
      // student nobody named.
      final reading = parser.fromPhoto([line('1 Aarav 18', 0), line('Diya 14', 30), line('3 Kabir 9', 60)]);
      expect(marks(reading), {101: '18', 102: '14', 103: '9'});
    });

    test('more marks than students', () {
      final small = MarksParser([student(1)]);
      final reading = small.fromPhoto([line('5', 0), line('6', 30)]);
      expect(marks(reading), {1: '5'});
      expect(reading.issues, [const ReadIssue(ReadIssueKind.extraValue, value: ReadMark.mark('6'))]);
    });

    test('nothing, or only words', () {
      expect(parser.fromPhoto(const []).isEmpty, isTrue);
      expect(parser.fromPhoto([line('Weekly test', 0), line('', 30)]).isEmpty, isTrue);
    });

    test('names written in Devanagari still count as names', () {
      expect(marks(parser.fromPhoto([line('2 दिया 14', 0)])), {102: '14'});
    });
  });

  group('checkMark', () {
    test('blank, in range, the maximum itself', () {
      expect(checkMark('', 20), isNull);
      expect(checkMark('0', 20), isNull);
      expect(checkMark('20', 20), isNull);
      expect(checkMark('19.5', 20), isNull);
    });

    test('over the maximum, or not a number', () {
      expect(checkMark('20.5', 20), MarkProblem.outOfRange);
      expect(checkMark('1.2.3', 20), MarkProblem.notANumber);
    });
  });
}
