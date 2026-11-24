import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'file_saver.dart';

/// One thing to put in the phone's calendar (docs/mobile-apps-review.md, M8,
/// 6.3): an exam paper with its times, or a holiday that lasts whole days.
class CalendarItem {
  const CalendarItem.timed({
    required this.uid,
    required this.title,
    required this.day,
    required String this.start,
    required String this.end,
    this.location,
    this.note,
  }) : lastDay = null;

  /// Whole days, [day] to [lastDay] inclusive.
  const CalendarItem.allDay({required this.uid, required this.title, required this.day, this.lastDay, this.note})
    : start = null,
      end = null,
      location = null;

  /// Stable across exports, so importing the same file twice updates rather
  /// than duplicates in most calendar apps.
  final String uid;
  final String title;
  final DateTime day;

  /// `HH:mm` on the school's clock, for a timed item.
  final String? start;
  final String? end;
  final DateTime? lastDay;
  final String? location;
  final String? note;
}

/// The items as an iCalendar (.ics) file - the format every phone and email
/// calendar reads.
///
/// Times are written as the school's local time with no zone ("floating"),
/// which a calendar shows as written: a 9:00 exam stays 9:00 on a parent's
/// phone, whatever zone the phone thinks it is in.
String calendarFile(List<CalendarItem> items, {required String name, DateTime? now}) {
  final stamp = _instant((now ?? DateTime.now()).toUtc());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//School365ai//Family app//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_text(name)}',
  ];

  for (final item in items) {
    lines.addAll(['BEGIN:VEVENT', 'UID:${item.uid}@school365ai.com', 'DTSTAMP:$stamp', 'SUMMARY:${_text(item.title)}']);

    if (item.start != null && item.end != null) {
      lines.add('DTSTART:${_date(item.day)}T${_time(item.start!)}');
      lines.add('DTEND:${_date(item.day)}T${_time(item.end!)}');
    } else {
      // An all-day event ends the day after its last day (RFC 5545).
      final last = item.lastDay ?? item.day;
      lines.add('DTSTART;VALUE=DATE:${_date(item.day)}');
      lines.add('DTEND;VALUE=DATE:${_date(last.add(const Duration(days: 1)))}');
    }

    if (item.location != null && item.location!.trim().isNotEmpty) lines.add('LOCATION:${_text(item.location!)}');
    if (item.note != null && item.note!.trim().isNotEmpty) lines.add('DESCRIPTION:${_text(item.note!)}');
    lines.add('END:VEVENT');
  }

  lines.add('END:VCALENDAR');

  // Lines end in CRLF, as the format requires.
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _date(DateTime day) => '${day.year}${_two(day.month)}${_two(day.day)}';

String _time(String hhmm) {
  final parts = hhmm.split(':');
  return '${_two(int.parse(parts[0]))}${_two(int.parse(parts[1]))}00';
}

String _instant(DateTime utc) => '${_date(utc)}T${_two(utc.hour)}${_two(utc.minute)}${_two(utc.second)}Z';

/// Commas, semicolons, backslashes and new lines are escaped in text.
String _text(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n');

/// A line longer than 75 bytes is folded onto continuation lines starting
/// with a space (RFC 5545, 3.1).
String _fold(String line) {
  final bytes = utf8.encode(line);
  if (bytes.length <= 75) return line;

  final parts = <String>[];
  var current = StringBuffer();
  var size = 0;
  for (final rune in line.runes) {
    final char = String.fromCharCode(rune);
    final length = utf8.encode(char).length;
    if (size + length > (parts.isEmpty ? 75 : 74)) {
      parts.add(current.toString());
      current = StringBuffer();
      size = 0;
    }
    current.write(char);
    size += length;
  }
  parts.add(current.toString());

  return parts.join('\r\n ');
}

/// Hands a calendar file to the person: the share sheet on a phone (a
/// calendar app offers to add it), a download in a browser. Swappable in
/// tests.
typedef CalendarHandOff = Future<void> Function(String contents, String fileName);

final calendarHandOffProvider = Provider<CalendarHandOff>(
  (ref) => (contents, fileName) async {
    final bytes = utf8.encode(contents);
    if (kIsWeb) {
      saveBytes(fileName: fileName, bytes: bytes, mimeType: 'text/calendar');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: 'text/calendar', name: fileName)],
        fileNameOverrides: [fileName],
      ),
    );
  },
);
