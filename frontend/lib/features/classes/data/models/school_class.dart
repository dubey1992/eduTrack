class ClassSection {
  const ClassSection({
    required this.id,
    required this.schoolClassId,
    required this.name,
    required this.roomNumber,
    required this.classTeacherId,
    required this.classTeacherName,
  });

  factory ClassSection.fromJson(Map<String, dynamic> json) {
    return ClassSection(
      id: json['id'] as int,
      schoolClassId: json['school_class_id'] as int,
      name: json['name'] as String,
      roomNumber: json['room_number'] as String?,
      classTeacherId: json['class_teacher_id'] as int?,
      classTeacherName: json['class_teacher_name'] as String?,
    );
  }

  final int id;
  final int schoolClassId;
  final String name;
  final String? roomNumber;
  final int? classTeacherId;
  final String? classTeacherName;
}

class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.academicYearId,
    required this.academicYearName,
    required this.name,
    required this.level,
    required this.sections,
  });

  factory SchoolClass.fromJson(Map<String, dynamic> json) {
    return SchoolClass(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      academicYearId: json['academic_year_id'] as int,
      academicYearName: json['academic_year_name'] as String?,
      name: json['name'] as String,
      level: json['level'] as int,
      sections: (json['sections'] as List).cast<Map<String, dynamic>>().map(ClassSection.fromJson).toList(),
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final int academicYearId;
  final String? academicYearName;
  final String name;
  final int level;
  final List<ClassSection> sections;
}
