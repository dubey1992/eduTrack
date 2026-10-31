/// One section on the Students page's class list, with how many active
/// students it has (docs/onboarding.md).
class StudentSectionCount {
  const StudentSectionCount({required this.id, required this.name, required this.students});

  factory StudentSectionCount.fromJson(Map<String, dynamic> json) =>
      StudentSectionCount(id: json['id'] as int, name: json['name'] as String, students: json['students'] as int);

  final int id;
  final String name;
  final int students;
}

/// A class of the current year and its sections, in class order -
/// Nursery, LKG, UKG, Class 1 ...
class StudentClassGroup {
  const StudentClassGroup({
    required this.id,
    required this.name,
    required this.level,
    required this.schoolId,
    required this.schoolName,
    required this.academicYearName,
    required this.sections,
  });

  factory StudentClassGroup.fromJson(Map<String, dynamic> json) => StudentClassGroup(
    id: json['id'] as int,
    name: json['name'] as String,
    level: json['level'] as int,
    schoolId: json['school_id'] as int,
    schoolName: json['school_name'] as String,
    academicYearName: json['academic_year_name'] as String,
    sections: [for (final row in json['sections'] as List) StudentSectionCount.fromJson(row as Map<String, dynamic>)],
  );

  final int id;
  final String name;
  final int level;
  final int schoolId;
  final String schoolName;
  final String academicYearName;
  final List<StudentSectionCount> sections;

  /// "Class 5 - A", or just "Class 5" for a class with one section.
  String labelFor(StudentSectionCount section) => sections.length == 1 ? name : '$name - ${section.name}';
}
