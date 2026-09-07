/// Mirrors the backend's App\Enums\UserRole (backend CLAUDE.md rule 11).
enum UserRole {
  superAdmin('SUPER_ADMIN', 'Super Admin'),
  schoolAdmin('SCHOOL_ADMIN', 'School Admin'),
  hod('HOD', 'HOD'),
  teacher('TEACHER', 'Teacher'),
  staff('STAFF', 'Staff'),
  transportManager('TRANSPORT_MANAGER', 'Transport Manager');

  const UserRole(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static UserRole fromApiValue(String value) {
    return UserRole.values.firstWhere(
      (role) => role.apiValue == value,
      orElse: () => throw ArgumentError('Unknown role: $value'),
    );
  }
}
