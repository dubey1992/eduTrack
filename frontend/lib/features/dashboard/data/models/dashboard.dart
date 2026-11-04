/// The landing screen's figures, in the one shape every role shares.
///
/// The server decides what a role may see and puts it in [cards]; the client
/// renders whatever arrives rather than knowing six different layouts. That
/// keeps the authorization rules in one place - the API - instead of being
/// half-expressed by which widgets a screen happens to build.
class Dashboard {
  const Dashboard({
    required this.role,
    required this.asOf,
    required this.isWorkingDay,
    required this.holiday,
    required this.cards,
    required this.attendanceTrend,
    required this.attention,
    this.breakdowns = const [],
    this.schoolId,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    return Dashboard(
      role: json['role'] as String,
      asOf: json['as_of'] as String,
      isWorkingDay: json['is_working_day'] as bool? ?? true,
      holiday: json['holiday'] as String?,
      schoolId: json['school_id'] as int?,
      cards: (json['cards'] as List<dynamic>? ?? [])
          .map((card) => DashboardCard.fromJson(card as Map<String, dynamic>))
          .toList(),
      attendanceTrend: (json['attendance_trend'] as List<dynamic>? ?? [])
          .map((point) => TrendPoint.fromJson(point as Map<String, dynamic>))
          .toList(),
      attention: (json['attention'] as List<dynamic>? ?? [])
          .map((note) => AttentionNote.fromJson(note as Map<String, dynamic>))
          .toList(),
      breakdowns: (json['breakdowns'] as List<dynamic>? ?? [])
          .map((ring) => DashboardBreakdown.fromJson(ring as Map<String, dynamic>))
          .toList(),
    );
  }

  final String role;

  /// The school's date these figures describe - not the browser's.
  final String asOf;

  /// False on a weekend or a holiday, when "nothing marked today" is the
  /// expected state rather than something to chase.
  final bool isWorkingDay;
  final String? holiday;
  final int? schoolId;
  final List<DashboardCard> cards;
  final List<TrendPoint> attendanceTrend;
  final List<AttentionNote> attention;

  /// The rings: today's students and staff split by the register, and fees
  /// collected of what has fallen due. One school in view only.
  final List<DashboardBreakdown> breakdowns;
}

class DashboardCard {
  const DashboardCard({
    required this.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.tone,
  });

  factory DashboardCard.fromJson(Map<String, dynamic> json) {
    return DashboardCard(
      key: json['key'] as String,
      label: json['label'] as String,
      value: json['value'] as String,
      hint: json['hint'] as String?,
      tone: json['tone'] as String? ?? 'neutral',
    );
  }

  final String key;
  final String label;
  final String value;
  final String? hint;

  /// The value as the lines it should be drawn on. Money collected in several
  /// currencies arrives as "INR 2,002,000.00 + USD 1,234.50" - grouped by
  /// currency and never blended (CLAUDE.md rule 5) - and each currency gets a
  /// line of its own rather than wrapping mid-amount.
  List<String> get valueLines => value.split(' + ');

  /// 'warning' when the figure is something to act on, 'ok' when it is
  /// settled, 'neutral' when it is just a number.
  final String tone;

  bool get isWarning => tone == 'warning';

  /// Amber: not bad enough to warn about, not good enough to leave - an
  /// attendance rate between the bands (decided 2026-11-04).
  bool get isCaution => tone == 'caution';

  bool get isOk => tone == 'ok';
}

class TrendPoint {
  const TrendPoint({required this.date, required this.label, required this.attendanceRate});

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    return TrendPoint(
      date: json['date'] as String,
      label: json['label'] as String,
      attendanceRate: (json['attendance_rate'] as num?)?.toDouble(),
    );
  }

  final String date;
  final String label;

  /// Null when no register was taken that day - which is not the same as
  /// everybody being absent, and must not be drawn as zero.
  final double? attendanceRate;
}

class AttentionNote {
  const AttentionNote({required this.key, required this.message});

  factory AttentionNote.fromJson(Map<String, dynamic> json) {
    return AttentionNote(key: json['key'] as String, message: json['message'] as String);
  }

  final String key;
  final String message;
}

/// A whole split into parts, drawn as a ring: the server says what the parts
/// are and how big; the app only draws them.
class DashboardBreakdown {
  const DashboardBreakdown({
    required this.key,
    required this.title,
    required this.headline,
    required this.caption,
    required this.segments,
  });

  factory DashboardBreakdown.fromJson(Map<String, dynamic> json) {
    return DashboardBreakdown(
      key: json['key'] as String,
      title: json['title'] as String,
      headline: json['headline'] as String,
      caption: json['caption'] as String,
      segments: (json['segments'] as List<dynamic>? ?? [])
          .map((segment) => BreakdownSegment.fromJson(segment as Map<String, dynamic>))
          .toList(),
    );
  }

  final String key;
  final String title;

  /// The figure in the middle of the ring, e.g. "84%".
  final String headline;

  /// What the headline is of, e.g. "present of 250 marked".
  final String caption;
  final List<BreakdownSegment> segments;

  double get total => segments.fold(0, (sum, segment) => sum + segment.value);
}

class BreakdownSegment {
  const BreakdownSegment({required this.key, required this.label, required this.value, required this.display});

  factory BreakdownSegment.fromJson(Map<String, dynamic> json) {
    return BreakdownSegment(
      key: json['key'] as String,
      label: json['label'] as String,
      value: (json['value'] as num).toDouble(),
      display: json['display'] as String,
    );
  }

  final String key;
  final String label;
  final double value;

  /// The value as a person reads it: a count, or an amount in the school's
  /// currency.
  final String display;
}
