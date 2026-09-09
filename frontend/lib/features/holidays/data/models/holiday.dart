enum HolidayType {
  national('national', 'National'),
  religious('religious', 'Religious'),
  schoolEvent('school_event', 'School Event'),
  vacation('vacation', 'Vacation');

  const HolidayType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static HolidayType fromApiValue(String value) => HolidayType.values.firstWhere((t) => t.apiValue == value);
}

/// The short form both attendance registers and the teaching-report
/// summary carry when the selected date is on the school's calendar.
class HolidaySummary {
  const HolidaySummary({required this.id, required this.name, required this.type});

  factory HolidaySummary.fromJson(Map<String, dynamic> json) {
    return HolidaySummary(
      id: json['id'] as int,
      name: json['name'] as String,
      type: HolidayType.fromApiValue(json['type'] as String),
    );
  }

  final int id;
  final String name;
  final HolidayType type;
}

/// One holiday or break on a school's calendar - an inclusive date range
/// (a single day has [startDate] == [endDate]).
class Holiday {
  const Holiday({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.name,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.days,
  });

  factory Holiday.fromJson(Map<String, dynamic> json) {
    return Holiday(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      name: json['name'] as String,
      type: HolidayType.fromApiValue(json['type'] as String),
      startDate: json['start_date'] as String,
      endDate: json['end_date'] as String,
      days: json['days'] as int,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final String name;
  final HolidayType type;

  /// `yyyy-MM-dd`, as the API sends them.
  final String startDate;
  final String endDate;
  final int days;

  bool get isSingleDay => startDate == endDate;
}
