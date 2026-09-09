class Subject {
  const Subject({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.departmentId,
    required this.departmentName,
    required this.code,
    required this.name,
    required this.minClassLevel,
    required this.maxClassLevel,
    required this.leadTeacherId,
    required this.leadTeacherName,
  });

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      departmentId: json['department_id'] as int,
      departmentName: json['department_name'] as String?,
      code: json['code'] as String,
      name: json['name'] as String,
      minClassLevel: json['min_class_level'] as int,
      maxClassLevel: json['max_class_level'] as int,
      leadTeacherId: json['lead_teacher_id'] as int?,
      leadTeacherName: json['lead_teacher_name'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final int departmentId;
  final String? departmentName;
  final String code;
  final String name;
  final int minClassLevel;
  final int maxClassLevel;
  final int? leadTeacherId;
  final String? leadTeacherName;
}
