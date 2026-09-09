enum StudentStatus {
  active('active'),
  inactive('inactive');

  const StudentStatus(this.apiValue);

  final String apiValue;

  static StudentStatus fromApiValue(String value) => StudentStatus.values.firstWhere((s) => s.apiValue == value);
}

class Student {
  const Student({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.classSectionId,
    required this.classSectionName,
    required this.admissionNumber,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.rollNumber,
    required this.guardianName,
    required this.guardianMobile,
    required this.address,
    required this.status,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      classSectionId: json['class_section_id'] as int?,
      classSectionName: json['class_section_name'] as String?,
      admissionNumber: json['admission_number'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      name: json['name'] as String,
      rollNumber: json['roll_number'] as String?,
      guardianName: json['guardian_name'] as String,
      guardianMobile: json['guardian_mobile'] as String?,
      address: json['address'] as String?,
      status: StudentStatus.fromApiValue(json['status'] as String),
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final int? classSectionId;
  final String? classSectionName;
  final String admissionNumber;
  final String firstName;
  final String lastName;
  final String name;
  final String? rollNumber;
  final String guardianName;
  final String? guardianMobile;
  final String? address;
  final StudentStatus status;

  Student copyWith({StudentStatus? status}) {
    return Student(
      id: id,
      schoolId: schoolId,
      schoolName: schoolName,
      classSectionId: classSectionId,
      classSectionName: classSectionName,
      admissionNumber: admissionNumber,
      firstName: firstName,
      lastName: lastName,
      name: name,
      rollNumber: rollNumber,
      guardianName: guardianName,
      guardianMobile: guardianMobile,
      address: address,
      status: status ?? this.status,
    );
  }
}
