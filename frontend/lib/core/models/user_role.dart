/// Mirrors the backend's App\Enums\UserRole (backend CLAUDE.md rule 11).
enum UserRole {
  superAdmin('SUPER_ADMIN', 'Super Admin'),

  /// Reads every branch in a school group and writes into whichever it
  /// names. Not a platform role - see docs/branches.md.
  groupAdmin('GROUP_ADMIN', 'Group Admin'),
  schoolAdmin('SCHOOL_ADMIN', 'School Admin'),
  hod('HOD', 'HOD'),
  teacher('TEACHER', 'Teacher'),
  staff('STAFF', 'Staff'),
  transportManager('TRANSPORT_MANAGER', 'Transport Manager'),

  /// Runs payroll for their own school; otherwise an ordinary employee.
  /// See docs/payroll.md.
  accountant('ACCOUNTANT', 'Accountant');

  const UserRole(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Whether a form has to ask which school is deliberately *not* here: a
  /// School Admin spans a group or a single school depending on the school
  /// they are in, which a role cannot know. See
  /// AuthenticatedUser.picksSchool.

  /// Administers schools' own affairs - their own school, and every branch in
  /// its group where there is one. Mirrors the backend's
  /// UserRole::administersSchool().
  bool get administersSchool => this == UserRole.schoolAdmin || this == UserRole.groupAdmin;

  static UserRole fromApiValue(String value) {
    return UserRole.values.firstWhere(
      (role) => role.apiValue == value,
      orElse: () => throw ArgumentError('Unknown role: $value'),
    );
  }
}
