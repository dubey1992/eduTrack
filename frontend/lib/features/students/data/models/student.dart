enum StudentStatus {
  active('active'),
  inactive('inactive');

  const StudentStatus(this.apiValue);

  final String apiValue;

  static StudentStatus fromApiValue(String value) => StudentStatus.values.firstWhere((s) => s.apiValue == value);
}

/// The student's current bus route + stop (Phase 14), or absent when they
/// don't use school transport.
class StudentTransport {
  const StudentTransport({
    required this.routeId,
    required this.routeName,
    required this.routeLabel,
    required this.vehicleName,
    required this.stopId,
    required this.stopName,
  });

  factory StudentTransport.fromJson(Map<String, dynamic> json) {
    return StudentTransport(
      routeId: json['route_id'] as int,
      routeName: json['route_name'] as String,
      routeLabel: json['route_label'] as String,
      vehicleName: json['vehicle_name'] as String?,
      stopId: json['stop_id'] as int,
      stopName: json['stop_name'] as String,
    );
  }

  final int routeId;
  final String routeName;

  /// "Bus 04 - Green Park".
  final String routeLabel;
  final String? vehicleName;
  final int stopId;
  final String stopName;
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
    this.transport,
    this.guardianEmail,
    this.studentMobile,
    this.studentEmail,
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
      transport: json['transport'] == null
          ? null
          : StudentTransport.fromJson(json['transport'] as Map<String, dynamic>),
      guardianEmail: json['guardian_email'] as String?,
      studentMobile: json['student_mobile'] as String?,
      studentEmail: json['student_email'] as String?,
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
  final StudentTransport? transport;

  /// Contact details beyond the guardian's mobile - each optional, and each
  /// a place the school can reach the family (see Phase 16, email channel).
  final String? guardianEmail;
  final String? studentMobile;
  final String? studentEmail;

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
      transport: transport,
      guardianEmail: guardianEmail,
      studentMobile: studentMobile,
      studentEmail: studentEmail,
    );
  }
}
