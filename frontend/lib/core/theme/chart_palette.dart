import 'package:flutter/material.dart';

import 'app_colors.dart';

/// One colour of the dashboard's palette (decided 2026-11-04), with a
/// strong shade for bars, rings and icons and a soft one for the tinted
/// ground behind them - each in a light and a dark version, so a figure
/// keeps its colour in both themes without going neon or muddy.
class ChartHue {
  const ChartHue({required this.light, required this.dark, required this.lightSoft, required this.darkSoft});

  final Color light;
  final Color dark;
  final Color lightSoft;
  final Color darkSoft;

  Color strong(BuildContext context) => _isDark(context) ? dark : light;

  Color soft(BuildContext context) => _isDark(context) ? darkSoft : lightSoft;

  static bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
}

/// The colours a dashboard figure is drawn in, and the icon that goes with
/// it. Since 2026-11-21 navy and violet lead, beside green, gold, teal,
/// coral and friends, each still distinct from its neighbours - so a
/// colourful dashboard sits in the School365AI palette rather than against
/// it. Colour here says *which* figure it is; whether a figure is good or bad
/// is said separately, by the semantic colours in AppColors.
abstract final class ChartPalette {
  static const navy = ChartHue(
    light: Color(0xFF1D4E89),
    dark: Color(0xFF9CC2F2),
    lightSoft: Color(0xFFE8F0FA),
    darkSoft: Color(0xFF15304F),
  );
  static const green = ChartHue(
    light: Color(0xFF277B62),
    dark: Color(0xFF6FD3B0),
    lightSoft: Color(0xFFE5F4EC),
    darkSoft: Color(0xFF173A30),
  );
  static const violet = ChartHue(
    light: Color(0xFF5B3FB0),
    dark: Color(0xFFC3B0F2),
    lightSoft: Color(0xFFF0ECFB),
    darkSoft: Color(0xFF2B2250),
  );
  static const gold = ChartHue(
    light: Color(0xFFAD7531),
    dark: Color(0xFFE9B86F),
    lightSoft: Color(0xFFFFF0DB),
    darkSoft: Color(0xFF45300F),
  );
  static const berry = ChartHue(
    light: Color(0xFFB03A4A),
    dark: Color(0xFFF59AA5),
    lightSoft: Color(0xFFFCE9EC),
    darkSoft: Color(0xFF4A1C26),
  );
  static const teal = ChartHue(
    light: Color(0xFF2E7F86),
    dark: Color(0xFF79CDD3),
    lightSoft: Color(0xFFE3F3F4),
    darkSoft: Color(0xFF15363A),
  );
  static const mauve = ChartHue(
    light: Color(0xFF7A5AA6),
    dark: Color(0xFFC3AEE6),
    lightSoft: Color(0xFFF0EAF8),
    darkSoft: Color(0xFF2E2445),
  );
  static const coral = ChartHue(
    light: Color(0xFFC8643E),
    dark: Color(0xFFF2A27F),
    lightSoft: Color(0xFFFDEDE4),
    darkSoft: Color(0xFF4A2516),
  );
  static const sky = ChartHue(
    light: Color(0xFF3F6C99),
    dark: Color(0xFF94BCE3),
    lightSoft: Color(0xFFE7EFF7),
    darkSoft: Color(0xFF1A2C40),
  );

  /// Used in turn for a figure this file does not name, so a new card the
  /// server starts sending is still coloured rather than left grey.
  static const _sequence = [navy, green, violet, gold, teal, mauve, coral, sky, berry];

  /// Each dashboard card and trend the server sends, by its key.
  static const _byKey = <String, (ChartHue, IconData)>{
    'students': (navy, Icons.school_outlined),
    'active_students': (navy, Icons.school_outlined),
    // The roll by gender (docs/dashboard.md).
    'boys': (sky, Icons.boy_outlined),
    'girls': (berry, Icons.girl_outlined),
    'gender_other': (mauve, Icons.people_outline),
    'staff': (violet, Icons.badge_outlined),
    'teachers': (violet, Icons.groups_outlined),
    'attendance': (green, Icons.fact_check_outlined),
    'student_attendance_rate': (green, Icons.fact_check_outlined),
    'staff_attendance_rate': (teal, Icons.how_to_reg_outlined),
    'transport': (gold, Icons.directions_bus_outlined),
    'routes': (gold, Icons.alt_route_outlined),
    'running': (coral, Icons.directions_bus_filled_outlined),
    'completed': (green, Icons.flag_outlined),
    'performance': (mauve, Icons.emoji_events_outlined),
    'schools': (teal, Icons.apartment_outlined),
    'branches': (teal, Icons.account_tree_outlined),
    'departments': (teal, Icons.apartment_outlined),
    'users': (mauve, Icons.manage_accounts_outlined),
    'collected': (green, Icons.payments_outlined),
    'outstanding': (coral, Icons.pending_actions_outlined),
    'fees_collected': (green, Icons.payments_outlined),
    'fees_outstanding': (coral, Icons.account_balance_wallet_outlined),
    'fees_overdue': (berry, Icons.schedule_outlined),
    'periods': (navy, Icons.schedule_outlined),
    'reports': (mauve, Icons.edit_note_outlined),
    'reviews': (mauve, Icons.rate_review_outlined),
    'register': (green, Icons.checklist_outlined),
    'payroll': (violet, Icons.receipt_long_outlined),
    'salaries': (coral, Icons.price_change_outlined),
    'unpaid': (berry, Icons.request_quote_outlined),
    'leave': (sky, Icons.event_busy_outlined),
    'inbox': (navy, Icons.mail_outline),
    // Charted on the Analytics page only.
    'teaching_coverage_rate': (mauve, Icons.edit_note_outlined),
    'syllabus_topics_completed': (sky, Icons.menu_book_outlined),
    'test_average': (violet, Icons.emoji_events_outlined),
    'active_staff': (violet, Icons.badge_outlined),
    'fee_outstanding': (coral, Icons.account_balance_wallet_outlined),
    'fee_overdue': (berry, Icons.schedule_outlined),
  };

  /// Figures where a fall is the good news, so a change is coloured the
  /// other way round.
  static const lowerIsBetter = {'fee_outstanding', 'fee_overdue'};

  static ChartHue hueFor(String key) => _byKey[key]?.$1 ?? _sequence[key.hashCode.abs() % _sequence.length];

  static IconData iconFor(String key) => _byKey[key]?.$2 ?? Icons.insights_outlined;
}

/// Where an attendance percentage falls (decided 2026-11-04): at or above
/// [good] is green, below [poor] is red, between is amber. The server's
/// school/dashboard.py holds the same two numbers for the card it sends.
abstract final class AttendanceBands {
  static const double good = 90;
  static const double poor = 75;

  /// The measures charted as an attendance percentage.
  static const measures = {'student_attendance_rate', 'staff_attendance_rate'};

  static AttendanceBand of(double rate) => rate >= good
      ? AttendanceBand.good
      : rate >= poor
      ? AttendanceBand.fair
      : AttendanceBand.poor;
}

enum AttendanceBand { good, fair, poor }

extension AttendanceBandColour on AttendanceBand {
  /// The semantic colour of the band: success, warning or danger.
  Color colour(BuildContext context) {
    final colours = context.appColors;

    return switch (this) {
      AttendanceBand.good => colours.success,
      AttendanceBand.fair => colours.warning,
      AttendanceBand.poor => colours.danger,
    };
  }

  String get label => switch (this) {
    AttendanceBand.good => '${AttendanceBands.good.toInt()}% and above',
    AttendanceBand.fair => '${AttendanceBands.poor.toInt()}-${AttendanceBands.good.toInt() - 1}%',
    AttendanceBand.poor => 'Below ${AttendanceBands.poor.toInt()}%',
  };
}
