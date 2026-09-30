import 'dart:io';

import 'package:edutrack_app/core/utils/date_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every date a person reads is written US-style - 09/29/2026 - because that
/// is what the server writes into messages, onto receipts and into the PDFs,
/// and a date that reads two ways depending on where you meet it is a date
/// nobody can check.
void main() {
  group('the one format', () {
    test('a date is month, day, year', () {
      expect(formatDate(DateTime(2026, 9, 29)), '09/29/2026');
    });

    test('a date and time keep the same order, with a 12-hour clock', () {
      expect(formatDateTime(DateTime(2026, 9, 29, 19, 42)), '09/29/2026 7:42 PM');
    });

    test('an ISO string from the server reads the same way', () {
      expect(formatIsoDate('2026-09-29'), '09/29/2026');
    });

    test('something unparseable is shown rather than swallowed', () {
      expect(formatIsoDate('whenever'), 'whenever');
      expect(formatIsoDate(null), '-');
    });

    test('what goes to the API stays ISO, whatever people read', () {
      expect(apiDate(DateTime(2026, 9, 29)), '2026-09-29');
    });
  });

  group('the sweep', () {
    /// A screen that formats its own date is how the two orders get mixed:
    /// the communication log compared the server's 09/29/2026 against
    /// "29 Sep 2026" for a year, so "sent today" was never true.
    test('no screen writes a date in any other order', () {
      final offenders = <String>[];
      // The bug class is the day coming before the month: "29 Sep 2026" or
      // 29/09/2026. A long US heading ("Tuesday, September 29, 2026"), a
      // weekday on its own, and the ISO wire format are all fine - none of
      // them can be read two ways.
      final dayBeforeMonth = RegExp(r"DateFormat\('[^']*(d+ +MMM|dd?/MM|dd?-MM|d/M[^M])[^']*'\)");

      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('date_format.dart')) continue;

        for (final match in dayBeforeMonth.allMatches(file.readAsStringSync())) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }

      expect(offenders, isEmpty, reason: 'use formatDate/formatDateTime so every date reads the same way');
    });

    /// The subtler half of the same bug, and the one that got past the
    /// check above: DateFormat.yMMMd() names no pattern at all, so what it
    /// prints is whatever locale the browser reports. It read "Sep 29,
    /// 2026" on the machine it was written on and "29 Sep 2026" on a UK
    /// one - day before month, on four screens, without a single character
    /// of the app changing.
    ///
    /// Month-only labels are left alone: "September 2026" carries no day to
    /// put in the wrong place.
    test('no screen lets the browser decide how a date is written', () {
      final offenders = <String>[];
      // A named constructor carrying a day: yMd, yMMMd, yMMMMEEEEd, Md...
      final localeDecides = RegExp(r'DateFormat\.(y?M+E*d|d\w*)\(');

      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('date_format.dart')) continue;

        for (final match in localeDecides.allMatches(file.readAsStringSync())) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }

      expect(offenders, isEmpty, reason: 'use formatDate so the order never depends on the reader');
    });
  });
}
