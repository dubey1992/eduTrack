import '../../assessments/data/models/assessment_sheet.dart';

/// Marks read off a teacher's voice or a photo of the marks list, before the
/// teacher has checked them (docs/mobile-apps-review.md, M12, 1.7).
///
/// Nothing here touches the sheet: the review step shows a [MarksReading],
/// and only what the teacher confirms is typed into the sheet's boxes.

/// What was read for one student.
class ReadMark {
  const ReadMark.mark(String this.marks) : isAbsent = false, unreadable = null;

  const ReadMark.absent() : marks = null, isAbsent = true, unreadable = null;

  /// Something was there, but it is not a mark: "4q" in a photo, or "roll 12"
  /// with nothing after it. [raw] is what was seen, or empty when nothing was.
  const ReadMark.unreadable(String raw) : marks = null, isAbsent = false, unreadable = raw;

  final String? marks;
  final bool isAbsent;
  final String? unreadable;

  bool get isUnreadable => unreadable != null;

  @override
  bool operator ==(Object other) =>
      other is ReadMark && other.marks == marks && other.isAbsent == isAbsent && other.unreadable == unreadable;

  @override
  int get hashCode => Object.hash(marks, isAbsent, unreadable);

  @override
  String toString() => isAbsent ? 'absent' : (marks ?? 'unreadable($unreadable)');
}

/// Why something read could not be put against a student.
enum ReadIssueKind {
  /// A roll number that is nobody on this sheet.
  unknownRoll,

  /// More marks than there were students left to give them to.
  extraValue,

  /// The same student read twice; the later one is kept.
  readTwice,

  /// Something with digits in it that is not a mark, and belongs to nobody.
  unreadable,
}

class ReadIssue {
  const ReadIssue(this.kind, {this.roll, this.value});

  final ReadIssueKind kind;

  /// The roll number it was about, when there was one.
  final String? roll;

  /// What was read: the mark, Absent, or the unreadable text.
  final ReadMark? value;

  @override
  bool operator ==(Object other) =>
      other is ReadIssue && other.kind == kind && other.roll == roll && other.value == value;

  @override
  int get hashCode => Object.hash(kind, roll, value);

  @override
  String toString() => 'ReadIssue(${kind.name}, roll: $roll, value: $value)';
}

class MarksReading {
  const MarksReading({required this.byStudent, required this.issues});

  /// By student id.
  final Map<int, ReadMark> byStudent;
  final List<ReadIssue> issues;

  /// Nothing heard or seen that looks like a mark at all.
  bool get isEmpty => byStudent.isEmpty && issues.isEmpty;
}

/// One line of text found in a photo, with where it sits on the page.
class ReadLine {
  const ReadLine({required this.text, required this.top, required this.bottom, required this.left});

  final String text;
  final double top;
  final double bottom;
  final double left;

  double get middle => (top + bottom) / 2;
  double get height => bottom - top;
}

/// What is wrong with a typed or read mark, before anything is sent.
enum MarkProblem { notANumber, outOfRange }

MarkProblem? checkMark(String text, double maxMarks) {
  final value = text.trim();
  if (value.isEmpty) return null;
  final parsed = double.tryParse(value);
  if (parsed == null) return MarkProblem.notANumber;
  if (parsed < 0 || parsed > maxMarks) return MarkProblem.outOfRange;
  return null;
}

/// Turns heard words or a photo's lines into marks against the sheet's
/// students. Pure Dart, shared by voice and camera.
///
/// The rules, in short:
/// - "roll 12 45" (or "roll 12, 45", "roll number 12 forty five") gives roll
///   12 a 45; "roll 7 absent" marks roll 7 absent.
/// - Two numbers alone, "12 45", are a roll and a mark when 12 is a roll on
///   the sheet; so are comma-separated pairs, "12 45, 13 40".
/// - Otherwise the numbers are marks in the sheet's order (which is roll
///   order), from [fromSpeech]'s `startAt` - for voice, the first student
///   without a mark, so a class can be read out in several goes.
/// - A photo line whose first number is a roll on the sheet gives that
///   student the next number on the line; lines with only a mark fill the
///   remaining students in order.
class MarksParser {
  MarksParser(List<SheetEntry> entries)
    : _entries = entries,
      _byRoll = {
        for (final entry in entries)
          if (entry.rollNumber != null && entry.rollNumber!.trim().isNotEmpty) _rollKey(entry.rollNumber!): entry,
      };

  final List<SheetEntry> _entries;
  final Map<String, SheetEntry> _byRoll;

  /// The first student with no mark and not absent - where a run of spoken
  /// marks picks up. Zero for a sheet with nobody marked, and also for a
  /// sheet with everyone marked (the teacher is then correcting from the top).
  static int firstUnmarked(List<SheetEntry> entries) {
    final index = entries.indexWhere((entry) => !entry.isMarked);
    return index < 0 ? 0 : index;
  }

  MarksReading fromSpeech(String heard, {int startAt = 0}) {
    final collector = _Collector(_entries, startAt: startAt);
    final tokens = _tokens(heard, photo: false);

    // Split on the word "roll": what comes before it is a run of marks (or
    // pairs); each "roll ..." is one student.
    final free = <_Token>[];
    final rolls = <List<_Token>>[];
    for (final token in tokens) {
      if (token is _RollWord) {
        rolls.add([]);
      } else if (rolls.isEmpty) {
        free.add(token);
      } else {
        rolls.last.add(token);
      }
    }

    _readFree(free, collector);
    for (final segment in rolls) {
      _readRollSegment(segment, collector, extrasAreIssues: true);
    }
    return collector.finish();
  }

  MarksReading fromPhoto(List<ReadLine> lines) {
    final collector = _Collector(_entries, startAt: 0);

    for (final row in _rows(lines)) {
      final tokens = _tokens(row, photo: true);
      if (tokens.any((token) => token is _Word && _headerWords.contains(token.text))) continue;

      final rollAt = tokens.indexWhere((token) => token is _RollWord);
      if (rollAt >= 0) {
        _readRollSegment(tokens.sublist(rollAt + 1), collector, extrasAreIssues: false);
        continue;
      }
      _readPhotoRow(tokens, collector);
    }
    return collector.finish();
  }

  // --- Reading -------------------------------------------------------------

  void _readFree(List<_Token> tokens, _Collector collector) {
    final values = tokens.whereType<_Value>().toList();
    if (values.isEmpty) return;

    // "12 45": a roll and its mark, when 12 is somebody on the sheet.
    if (values.length == 2 && _student(values.first) != null) {
      collector.assign(_student(values.first)!, values.first.text, values.last.mark);
      return;
    }

    // "12 45, 13 40": pairs, every one of them led by a roll on the sheet.
    final groups = _split(tokens);
    final pairs = groups.length > 1 && groups.every((group) => group.length == 2 && _student(group.first) != null);
    if (pairs) {
      for (final group in groups) {
        collector.assign(_student(group.first)!, group.first.text, group.last.mark);
      }
      return;
    }

    for (final value in values) {
      collector.next(value.mark);
    }
  }

  /// What follows the word "roll": the roll, then the mark or Absent.
  void _readRollSegment(List<_Token> tokens, _Collector collector, {required bool extrasAreIssues}) {
    final values = tokens.whereType<_Value>().toList();
    final garbage = tokens.whereType<_Garbage>().map((token) => token.text).toList();
    if (values.isEmpty || values.first is! _Number || !(values.first as _Number).isWhole) {
      if (garbage.isNotEmpty) {
        collector.issue(ReadIssue(ReadIssueKind.unreadable, value: ReadMark.unreadable(garbage.first)));
      }
      return;
    }

    final roll = values.first.text;
    final student = _byRoll[_rollKey(roll)];
    final mark = values.length > 1 ? values[1].mark : ReadMark.unreadable(garbage.isEmpty ? '' : garbage.first);

    if (student == null) {
      collector.issue(ReadIssue(ReadIssueKind.unknownRoll, roll: roll, value: values.length > 1 ? mark : null));
    } else {
      collector.assign(student, roll, mark);
    }
    if (extrasAreIssues) {
      for (final extra in values.skip(2)) {
        collector.issue(ReadIssue(ReadIssueKind.extraValue, value: extra.mark));
      }
    }
  }

  /// One line of a photographed list: "12 Aarav Shah 45", "12. Diya AB",
  /// or a mark on its own when only the marks column was photographed.
  void _readPhotoRow(List<_Token> tokens, _Collector collector) {
    final values = tokens.whereType<_Value>().toList();
    final garbage = tokens.whereType<_Garbage>().map((token) => token.text).toList();
    final hasName = tokens.any((token) => token is _Word);
    final first = values.isEmpty ? null : values.first;
    final startsWithNumber = tokens.isNotEmpty && tokens.first is _Number;

    if (first != null && values.length >= 2 && _student(first) != null) {
      collector.assign(_student(first)!, first.text, values[1].mark);
      return;
    }
    if (first != null && values.length == 1 && startsWithNumber && _student(first) != null && hasName) {
      // A roll and a name, and no mark that could be read.
      collector.assign(_student(first)!, first.text, ReadMark.unreadable(garbage.isEmpty ? '' : garbage.first));
      return;
    }
    if (first != null && values.length >= 2 && hasName && startsWithNumber && first is _Number && first.isWhole) {
      collector.issue(ReadIssue(ReadIssueKind.unknownRoll, roll: first.text, value: values[1].mark));
      return;
    }

    // Words after the last number: a heading such as "Class 3 B - Spelling
    // test", not a row - on a list the mark comes after the name. Seen on a
    // phone 2026-11-25, where the 3 was taken as the first child's mark.
    final lastValueAt = tokens.lastIndexWhere((token) => token is _Value);
    if (hasName && lastValueAt >= 0 && tokens.skip(lastValueAt + 1).any((token) => token is _Word)) return;

    if (values.isEmpty) {
      // A mark that could not be read still takes its student's place, so
      // the marks below it do not slide up onto the wrong children.
      if (garbage.isNotEmpty && !hasName) collector.next(ReadMark.unreadable(garbage.first));
      return;
    }
    // A name and a mark ("Aarav Shah 45"): the mark is the last number.
    if (hasName) {
      collector.next(values.last.mark);
      return;
    }
    for (final value in values) {
      collector.next(value.mark);
    }
  }

  SheetEntry? _student(_Value value) => value is _Number && value.isWhole ? _byRoll[_rollKey(value.text)] : null;

  /// Values between commas or full stops.
  List<List<_Value>> _split(List<_Token> tokens) {
    final groups = <List<_Value>>[[]];
    for (final token in tokens) {
      if (token is _Break) {
        if (groups.last.isNotEmpty) groups.add([]);
      } else if (token is _Value) {
        groups.last.add(token);
      }
    }
    if (groups.last.isEmpty) groups.removeLast();
    return groups;
  }

  // --- Photo lines into rows -----------------------------------------------

  /// Lines side by side on the page are one row: ML Kit often reads the
  /// roll, the name and the mark of a table row as separate lines.
  static List<String> _rows(List<ReadLine> lines) {
    final sorted = [...lines.where((line) => line.text.trim().isNotEmpty)]
      ..sort((a, b) => a.middle.compareTo(b.middle));
    final rows = <List<ReadLine>>[];
    for (final line in sorted) {
      if (rows.isNotEmpty) {
        final anchor = rows.last.first;
        final tolerance = (anchor.height < line.height ? anchor.height : line.height) / 2;
        if ((line.middle - anchor.middle).abs() <= tolerance) {
          rows.last.add(line);
          continue;
        }
      }
      rows.add([line]);
    }
    return [for (final row in rows) (row..sort((a, b) => a.left.compareTo(b.left))).map((line) => line.text).join(' ')];
  }

  // --- Words into tokens ---------------------------------------------------

  static const _headerWords = {'max', 'maximum', 'total'};

  static List<_Token> _tokens(String text, {required bool photo}) {
    var prepared = _asciiDigits(text.toLowerCase()).replaceAll('½', '.5');
    // "45/50": the mark, out of the maximum.
    prepared = prepared.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*/\s*\d+(?:\.\d+)?'), (m) => m.group(1)!);
    prepared = prepared.replaceAll('-', ' ');
    // "roll no. 12", "roll number 12", "roll12" - and "role", as it is often heard.
    prepared = prepared.replaceAllMapped(
      RegExp(r'\b(?:roll|role|rol)\s*(?:number|num|no\.?)?\s*(?=\d|\s|$)'),
      (_) => ' roll ',
    );
    // A full stop or comma that is not inside a number ends a group.
    prepared = prepared.replaceAllMapped(RegExp(r'(\d)\.(?!\d)|(?<!\d)\.|[,;:\n]'), (m) => '${m.group(1) ?? ''} , ');

    final words = <String>[];
    for (final raw in prepared.split(RegExp(r'\s+'))) {
      if (raw.isEmpty) continue;
      if (raw == ',') {
        words.add(',');
        continue;
      }
      final word = raw.replaceAll(RegExp(r'^[^\p{L}\p{N}|]+|[^\p{L}\p{N}|.]+$', unicode: true), '');
      if (word.isNotEmpty) words.add(word);
    }

    final tokens = <_Token>[];
    var i = 0;
    while (i < words.length) {
      final word = words[i];
      if (word == ',' || word == 'next') {
        tokens.add(const _Break());
        i++;
        continue;
      }
      if (word == 'roll') {
        tokens.add(const _RollWord());
        i++;
        continue;
      }
      if (_absentWords.contains(word)) {
        tokens.add(const _AbsentValue());
        i++;
        continue;
      }
      if (word == 'out' && i + 2 < words.length && words[i + 1] == 'of') {
        // "45 out of 50": drop "out of 50".
        final skip = _readNumber(words, i + 2);
        if (skip != null) {
          i = skip.$2;
          continue;
        }
      }
      final number = _readNumber(words, i);
      if (number != null) {
        tokens.add(_Number(number.$1));
        i = number.$2;
        continue;
      }
      if (photo) {
        final fixed = _ocrDigits(word);
        if (fixed != null) {
          final number = _readNumber([fixed, ...words.sublist(i + 1)], 0);
          tokens.add(number != null ? _Number(number.$1) : _Garbage(word));
          i += number != null ? number.$2 : 1;
          continue;
        }
        if (RegExp(r'\d').hasMatch(word)) {
          tokens.add(_Garbage(word));
          i++;
          continue;
        }
      }
      if (RegExp(r'\p{L}', unicode: true).hasMatch(word)) tokens.add(_Word(word));
      i++;
    }
    return tokens;
  }

  static const _absentWords = {'absent', 'ab', 'abs', 'abt'};

  static const _units = {
    'zero': 0,
    'nil': 0,
    'nought': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };

  static const _tens = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  /// A number starting at [start], in digits or words, with any "point five"
  /// or "and a half" after it: the value and where reading stopped.
  static (double, int)? _readNumber(List<String> words, int start) {
    var i = start;
    double? value;
    final word = words[i];

    final digits = double.tryParse(word);
    if (digits != null && RegExp(r'^\d+(\.\d+)?$').hasMatch(word)) {
      value = digits;
      i++;
    } else if (_units.containsKey(word) || _tens.containsKey(word) || word == 'hundred') {
      final whole = _readWholeWords(words, i);
      value = whole.$1.toDouble();
      i = whole.$2;
    } else if (word == 'a' && i + 1 < words.length && words[i + 1] == 'hundred') {
      value = 100;
      i += 2;
    } else {
      return null;
    }

    // "point five", "point 5", "point two five".
    if (i + 1 < words.length && (words[i] == 'point' || words[i] == 'dot') && value == value.roundToDouble()) {
      final fraction = StringBuffer();
      var j = i + 1;
      while (j < words.length) {
        final next = words[j];
        if (RegExp(r'^\d+$').hasMatch(next)) {
          fraction.write(next);
          j++;
          break;
        }
        final unit = _units[next];
        if (unit == null || unit > 9) break;
        fraction.write(unit);
        j++;
      }
      if (fraction.isNotEmpty) {
        value = double.parse('${value.round()}.$fraction');
        i = j;
      }
    }

    // "and a half", "and half", "half".
    final rest = words.skip(i).take(3).toList();
    if (rest.length >= 3 && rest[0] == 'and' && rest[1] == 'a' && rest[2] == 'half') {
      value += 0.5;
      i += 3;
    } else if (rest.length >= 2 && rest[0] == 'and' && rest[1] == 'half') {
      value += 0.5;
      i += 2;
    } else if (rest.isNotEmpty && rest[0] == 'half') {
      value += 0.5;
      i += 1;
    }
    return (value, i);
  }

  /// "forty five", "one hundred and five", "twelve": up to the next word
  /// that does not carry the number on.
  static (int, int) _readWholeWords(List<String> words, int start) {
    var i = start;
    var value = 0;
    final first = words[i];

    if (first == 'hundred') return (100, i + 1);

    final unit = _units[first];
    if (unit != null) {
      value = unit;
      i++;
      if (i < words.length && words[i] == 'hundred') {
        value *= 100;
        i++;
        // "one hundred and five"; an "and" with no number after it is not ours.
        var j = i;
        if (j < words.length && words[j] == 'and') j++;
        if (j < words.length && (_units.containsKey(words[j]) || _tens.containsKey(words[j]))) {
          final more = _readWholeWords(words, j);
          if (more.$1 < 100) {
            value += more.$1;
            i = more.$2;
          }
        }
      }
      return (value, i);
    }

    value = _tens[first]!;
    i++;
    if (i < words.length) {
      final next = _units[words[i]];
      if (next != null && next >= 1 && next <= 9) {
        value += next;
        i++;
      }
    }
    return (value, i);
  }

  /// What handwriting and ML Kit make of digits: O for 0, l for 1, S for 5.
  /// Only for short words that already hold a digit - "Sita" stays a name.
  static String? _ocrDigits(String word) {
    if (word.length > 6 || !RegExp(r'\d').hasMatch(word)) return null;
    if (!RegExp(r'^[0-9oil|sbz.]+$').hasMatch(word)) return null;
    const swaps = {'o': '0', 'i': '1', 'l': '1', '|': '1', 's': '5', 'b': '8', 'z': '2'};
    final fixed = word.split('').map((char) => swaps[char] ?? char).join();
    return RegExp(r'^\d+(\.\d+)?$').hasMatch(fixed) ? fixed : null;
  }

  /// Devanagari digits, as a phone set to Hindi may write them.
  static String _asciiDigits(String text) {
    const devanagari = '०१२३४५६७८९';
    final out = StringBuffer();
    for (final rune in text.runes) {
      final at = devanagari.indexOf(String.fromCharCode(rune));
      out.write(at >= 0 ? '$at' : String.fromCharCode(rune));
    }
    return out.toString();
  }

  /// "07" and "7" are the same roll.
  static String _rollKey(String roll) {
    final trimmed = roll.trim().toLowerCase();
    final stripped = trimmed.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return stripped;
  }
}

/// Gathers what was read, and what could not be placed.
class _Collector {
  _Collector(this._entries, {required int startAt}) : _startAt = startAt.clamp(0, _entries.length);

  final List<SheetEntry> _entries;
  final int _startAt;
  final Map<int, ReadMark> _byStudent = {};
  final List<ReadIssue> _issues = [];

  /// Marks with no roll: placed after the rest, on the students nobody named.
  final List<ReadMark> _queued = [];

  void assign(SheetEntry student, String roll, ReadMark mark) {
    final before = _byStudent[student.studentId];
    if (before != null) _issues.add(ReadIssue(ReadIssueKind.readTwice, roll: roll, value: before));
    _byStudent[student.studentId] = mark;
  }

  void next(ReadMark mark) => _queued.add(mark);

  void issue(ReadIssue issue) => _issues.add(issue);

  MarksReading finish() {
    var index = _startAt;
    for (final mark in _queued) {
      while (index < _entries.length && _byStudent.containsKey(_entries[index].studentId)) {
        index++;
      }
      if (index >= _entries.length) {
        _issues.add(ReadIssue(ReadIssueKind.extraValue, value: mark));
        continue;
      }
      _byStudent[_entries[index].studentId] = mark;
      index++;
    }
    return MarksReading(byStudent: Map.unmodifiable(_byStudent), issues: List.unmodifiable(_issues));
  }
}

sealed class _Token {
  const _Token();
}

/// Something that can be a mark: a number, or Absent.
sealed class _Value extends _Token {
  const _Value();

  String get text;
  ReadMark get mark;
}

class _Number extends _Value {
  const _Number(this.value);

  final double value;

  bool get isWhole => value == value.roundToDouble();

  @override
  String get text {
    if (isWhole) return value.round().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  @override
  ReadMark get mark => ReadMark.mark(text);
}

class _AbsentValue extends _Value {
  const _AbsentValue();

  @override
  String get text => 'absent';

  @override
  ReadMark get mark => const ReadMark.absent();
}

class _RollWord extends _Token {
  const _RollWord();
}

class _Break extends _Token {
  const _Break();
}

class _Word extends _Token {
  const _Word(this.text);

  final String text;
}

class _Garbage extends _Token {
  const _Garbage(this.text);

  final String text;
}
