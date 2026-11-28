/// What a trusted school computer keeps for working offline
/// (docs/offline-web.md, O2): the answer to `GET offline/snapshot`, read
/// straight from the JSON kept on the computer.
class OfflineSnapshot {
  const OfflineSnapshot({
    required this.generatedAt,
    required this.school,
    required this.classes,
    required this.students,
    this.staff,
    this.dues,
  });

  factory OfflineSnapshot.fromJson(Map<String, dynamic> json) {
    final dues = json['dues'] as Map<String, dynamic>?;
    return OfflineSnapshot(
      generatedAt: DateTime.parse(json['generated_at'] as String).toLocal(),
      school: OfflineSchool.fromJson(json['school'] as Map<String, dynamic>),
      classes: [
        for (final c in json['classes'] as List<dynamic>)
          (id: (c as Map<String, dynamic>)['id'] as int, name: c['name'] as String),
      ],
      students: [for (final s in json['students'] as List<dynamic>) OfflineStudent.fromJson(s as Map<String, dynamic>)],
      staff: json['staff'] == null
          ? null
          : [for (final s in json['staff'] as List<dynamic>) OfflineStaff.fromJson(s as Map<String, dynamic>)],
      dues: dues == null
          ? null
          : {
              for (final entry in dues.entries)
                int.parse(entry.key): [
                  for (final d in entry.value as List<dynamic>) OfflineDue.fromJson(d as Map<String, dynamic>),
                ],
            },
    );
  }

  /// When the server put it together - what "as of" means on every screen.
  final DateTime generatedAt;
  final OfflineSchool school;
  final List<({int id, String name})> classes;
  final List<OfflineStudent> students;

  /// Null for someone who may not see staff.
  final List<OfflineStaff>? staff;

  /// Fee lines still owed, by student id; null for someone who may not see fees.
  final Map<int, List<OfflineDue>>? dues;

  List<OfflineDue> duesOf(int studentId) => dues?[studentId] ?? const [];
}

class OfflineSchool {
  const OfflineSchool({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.email,
    required this.currencyCode,
  });

  factory OfflineSchool.fromJson(Map<String, dynamic> json) => OfflineSchool(
    id: json['id'] as int,
    name: json['name'] as String,
    address: json['address'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    currencyCode: json['currency_code'] as String,
  );

  final int id;
  final String name;
  final String address;
  final String phone;
  final String email;
  final String currencyCode;
}

class OfflineStudent {
  const OfflineStudent({
    required this.id,
    required this.name,
    required this.admissionNumber,
    this.rollNumber,
    this.classSectionId,
    this.className,
    this.guardianName,
    this.guardianMobile,
  });

  factory OfflineStudent.fromJson(Map<String, dynamic> json) => OfflineStudent(
    id: json['id'] as int,
    name: json['name'] as String,
    admissionNumber: json['admission_number'] as String,
    rollNumber: json['roll_number'] as String?,
    classSectionId: json['class_section_id'] as int?,
    className: json['class_name'] as String?,
    guardianName: json['guardian_name'] as String?,
    guardianMobile: json['guardian_mobile'] as String?,
  );

  final int id;
  final String name;
  final String admissionNumber;
  final String? rollNumber;
  final int? classSectionId;
  final String? className;
  final String? guardianName;
  final String? guardianMobile;

  /// Name, admission number, roll number or guardian, any part of it.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      name,
      admissionNumber,
      rollNumber ?? '',
      guardianName ?? '',
      guardianMobile ?? '',
    ].any((field) => field.toLowerCase().contains(q));
  }
}

class OfflineStaff {
  const OfflineStaff({
    required this.id,
    required this.name,
    required this.employeeId,
    this.department,
    this.designation,
    this.mobile,
    this.email,
  });

  factory OfflineStaff.fromJson(Map<String, dynamic> json) => OfflineStaff(
    id: json['id'] as int,
    name: json['name'] as String,
    employeeId: json['employee_id'] as String,
    department: json['department'] as String?,
    designation: json['designation'] as String?,
    mobile: json['mobile'] as String?,
    email: json['email'] as String?,
  );

  final int id;
  final String name;
  final String employeeId;
  final String? department;
  final String? designation;
  final String? mobile;
  final String? email;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      name,
      employeeId,
      department ?? '',
      designation ?? '',
      mobile ?? '',
    ].any((f) => f.toLowerCase().contains(q));
  }
}

/// One fee line still owed, as it stood when the snapshot was made.
class OfflineDue {
  const OfflineDue({
    required this.id,
    required this.academicYearId,
    required this.academicYear,
    required this.feeHead,
    required this.label,
    required this.kind,
    required this.dueDate,
    required this.currencyCode,
    required this.balance,
    required this.isOverdue,
  });

  factory OfflineDue.fromJson(Map<String, dynamic> json) => OfflineDue(
    id: json['id'] as int,
    academicYearId: json['academic_year_id'] as int,
    academicYear: json['academic_year'] as String,
    feeHead: json['fee_head'] as String,
    label: json['label'] as String,
    kind: json['kind'] as String,
    dueDate: json['due_date'] as String,
    currencyCode: json['currency_code'] as String,
    balance: json['balance'] as String,
    isOverdue: json['is_overdue'] as bool,
  );

  final int id;
  final int academicYearId;
  final String academicYear;
  final String feeHead;
  final String label;
  final String kind;

  /// yyyy-MM-dd.
  final String dueDate;
  final String currencyCode;

  /// "3500.00".
  final String balance;
  final bool isOverdue;
}
