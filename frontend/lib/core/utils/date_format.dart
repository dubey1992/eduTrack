import 'package:intl/intl.dart';

/// How a date is written wherever a person reads one.
///
/// US order - 09/17/2026 - everywhere in the app, matching what the server
/// writes into messages and onto the PDF receipt, so the same date never reads
/// two ways depending on where you meet it. See App\Support\DateFormats.
///
/// This is presentation only. A date going to the API uses [apiDate], which is
/// ISO and must stay that way: every endpoint and every `date` column expects
/// it, and sending 09/17/2026 would simply be rejected.
final _display = DateFormat('MM/dd/yyyy');
final _displayWithTime = DateFormat('MM/dd/yyyy h:mm a');
final _wire = DateFormat('yyyy-MM-dd');

/// 09/17/2026
String formatDate(DateTime date) => _display.format(date);

/// 09/17/2026 7:42 AM
String formatDateTime(DateTime moment) => _displayWithTime.format(moment);

/// The same, from an ISO string. Returns the original text when it cannot be
/// parsed - showing a raw value is better than showing nothing at all.
String formatIsoDate(String? iso) {
  if (iso == null || iso.isEmpty) return '-';

  final parsed = DateTime.tryParse(iso);

  return parsed == null ? iso : _display.format(parsed);
}

/// yyyy-MM-dd, for the API. Never shown to anyone.
String apiDate(DateTime date) => _wire.format(date);
