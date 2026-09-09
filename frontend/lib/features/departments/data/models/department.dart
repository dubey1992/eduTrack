class Department {
  const Department({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.name,
    required this.hodUserId,
    required this.hodName,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      name: json['name'] as String,
      hodUserId: json['hod_user_id'] as int?,
      hodName: json['hod_name'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final String name;
  final int? hodUserId;
  final String? hodName;
}
