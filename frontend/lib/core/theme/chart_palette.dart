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
/// it. Colour here says *which* figure it is; whether a figure is good or bad
/// is said separately, by the semantic colours in AppColors.
abstract final class ChartPalette {
  static const blue = ChartHue(
    light: Color(0xFF2563EB),
    dark: Color(0xFF60A5FA),
    lightSoft: Color(0xFFE6EEFF),
    darkSoft: Color(0xFF16264A),
  );
  static const green = ChartHue(
    light: Color(0xFF059669),
    dark: Color(0xFF34D399),
    lightSoft: Color(0xFFE3F7EF),
    darkSoft: Color(0xFF0F3328),
  );
  static const violet = ChartHue(
    light: Color(0xFF7C3AED),
    dark: Color(0xFFA78BFA),
    lightSoft: Color(0xFFF0E9FF),
    darkSoft: Color(0xFF2A1C4A),
  );
  static const amber = ChartHue(
    light: Color(0xFFD97706),
    dark: Color(0xFFFBBF24),
    lightSoft: Color(0xFFFFF3DC),
    darkSoft: Color(0xFF3D2A0A),
  );
  static const rose = ChartHue(
    light: Color(0xFFE11D48),
    dark: Color(0xFFFB7185),
    lightSoft: Color(0xFFFFE7EC),
    darkSoft: Color(0xFF451622),
  );
  static const teal = ChartHue(
    light: Color(0xFF0D9488),
    dark: Color(0xFF2DD4BF),
    lightSoft: Color(0xFFE0F5F3),
    darkSoft: Color(0xFF0E3330),
  );
  static const indigo = ChartHue(
    light: Color(0xFF4F46E5),
    dark: Color(0xFF818CF8),
    lightSoft: Color(0xFFECEBFF),
    darkSoft: Color(0xFF1F1D4A),
  );
  static const orange = ChartHue(
    light: Color(0xFFEA580C),
    dark: Color(0xFFFB923C),
    lightSoft: Color(0xFFFFEDE2),
    darkSoft: Color(0xFF41200D),
  );
  static const cyan = ChartHue(
    light: Color(0xFF0891B2),
    dark: Color(0xFF22D3EE),
    lightSoft: Color(0xFFE0F5FA),
    darkSoft: Color(0xFF0C2F3A),
  );

  /// Used in turn for a figure this file does not name, so a new card the
  /// server starts sending is still coloured rather than left grey.
  static const _sequence = [blue, green, violet, amber, teal, indigo, orange, cyan, rose];

  /// Each dashboard card and trend the server sends, by its key.
  static const _byKey = <String, (ChartHue, IconData)>{
    'students': (blue, Icons.school_outlined),
    'active_students': (blue, Icons.school_outlined),
    'staff': (violet, Icons.badge_outlined),
    'teachers': (violet, Icons.groups_outlined),
    'attendance': (green, Icons.fact_check_outlined),
    'student_attendance_rate': (green, Icons.fact_check_outlined),
    'staff_attendance_rate': (teal, Icons.how_to_reg_outlined),
    'transport': (amber, Icons.directions_bus_outlined),
    'routes': (amber, Icons.alt_route_outlined),
    'running': (orange, Icons.directions_bus_filled_outlined),
    'completed': (green, Icons.flag_outlined),
    'performance': (indigo, Icons.emoji_events_outlined),
    'schools': (teal, Icons.apartment_outlined),
    'branches': (teal, Icons.account_tree_outlined),
    'departments': (teal, Icons.apartment_outlined),
    'users': (indigo, Icons.manage_accounts_outlined),
    'collected': (green, Icons.payments_outlined),
    'outstanding': (orange, Icons.pending_actions_outlined),
    'fees_collected': (green, Icons.payments_outlined),
    'fees_outstanding': (orange, Icons.account_balance_wallet_outlined),
    'fees_overdue': (rose, Icons.schedule_outlined),
    'periods': (blue, Icons.schedule_outlined),
    'reports': (indigo, Icons.edit_note_outlined),
    'reviews': (indigo, Icons.rate_review_outlined),
    'register': (green, Icons.checklist_outlined),
    'payroll': (violet, Icons.receipt_long_outlined),
    'salaries': (orange, Icons.price_change_outlined),
    'unpaid': (rose, Icons.request_quote_outlined),
    'leave': (cyan, Icons.event_busy_outlined),
    'inbox': (blue, Icons.mail_outline),
    // Charted on the Analytics page only.
    'teaching_coverage_rate': (indigo, Icons.edit_note_outlined),
    'syllabus_topics_completed': (cyan, Icons.menu_book_outlined),
    'test_average': (violet, Icons.emoji_events_outlined),
    'active_staff': (violet, Icons.badge_outlined),
    'fee_outstanding': (orange, Icons.account_balance_wallet_outlined),
    'fee_overdue': (rose, Icons.schedule_outlined),
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
