class AcademicYear {
  const AcademicYear({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.isCurrent,
  });

  factory AcademicYear.fromJson(Map<String, dynamic> json) {
    return AcademicYear(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      name: json['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      isCurrent: json['is_current'] as bool,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool isCurrent;

  AcademicYear copyWith({bool? isCurrent}) {
    return AcademicYear(
      id: id,
      schoolId: schoolId,
      schoolName: schoolName,
      name: name,
      startDate: startDate,
      endDate: endDate,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }
}
