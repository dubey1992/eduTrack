/// The signed-in user's own account, as the My Profile screen sees it.
///
/// Every role has one, the Super Admin included. [employment] and [address]
/// only mean something for someone with a staff record at a school; the
/// work details are kept by the school's administrators and are read-only
/// here.
class Profile {
  const Profile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.name,
    required this.email,
    required this.mobile,
    required this.role,
    required this.roleLabel,
    required this.schoolName,
    required this.photoUrl,
    required this.hasStaffRecord,
    required this.address,
    required this.employment,
    required this.updatedAt,
    this.signsInWithPasscode = false,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final employment = json['employment'];

    return Profile(
      id: json['id'] as int,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      name: json['name'] as String,
      // Null for a Bus Attendant created without an address: they sign in
      // with a passcode, and the placeholder the server keeps is never shown.
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      role: json['role'] as String,
      roleLabel: json['role_label'] as String? ?? json['role'] as String,
      schoolName: json['school_name'] as String?,
      photoUrl: json['photo_url'] as String?,
      hasStaffRecord: json['has_staff_record'] as bool? ?? false,
      address: json['address'] as String?,
      employment: employment is Map<String, dynamic> ? Employment.fromJson(employment) : null,
      updatedAt: json['updated_at'] as String?,
      signsInWithPasscode: json['signs_in_with'] == 'passcode',
    );
  }

  final int id;
  final String firstName;
  final String lastName;
  final String name;
  final String? email;
  final String? mobile;

  /// The API's role value, e.g. `TEACHER`.
  final String role;

  /// The same role, worded for display.
  final String roleLabel;
  final String? schoolName;

  /// Where the photo is served, relative to the API base, or null when there
  /// is none. Changes whenever the photo does.
  final String? photoUrl;

  /// Whether this account has a staff record - only then is there a home
  /// address to edit and work details to show.
  final bool hasStaffRecord;
  final String? address;
  final Employment? employment;
  final String? updatedAt;

  /// A Bus Attendant: signs in with a mobile number and passcode, has no
  /// password, and cannot change the email or mobile their school keeps.
  final bool signsInWithPasscode;
}

/// The staff record's work details, read-only on the profile.
class Employment {
  const Employment({
    required this.employeeId,
    required this.departmentName,
    required this.designation,
    required this.joiningDate,
    required this.joiningDateLabel,
  });

  factory Employment.fromJson(Map<String, dynamic> json) {
    return Employment(
      employeeId: json['employee_id'] as String,
      departmentName: json['department_name'] as String?,
      designation: json['designation'] as String?,
      joiningDate: json['joining_date'] as String?,
      joiningDateLabel: json['joining_date_label'] as String?,
    );
  }

  final String employeeId;
  final String? departmentName;
  final String? designation;

  /// ISO date, e.g. `2024-06-01`.
  final String? joiningDate;

  /// The same date, already worded for display by the server.
  final String? joiningDateLabel;
}
