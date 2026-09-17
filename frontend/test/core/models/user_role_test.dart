import 'package:edutrack_app/core/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the Accountant role the backend sends', () {
    // An unknown role throws, and it throws while restoring a session - so a
    // role the backend knows and the app does not signs the person out of
    // every screen. Pinned for the newest role.
    expect(UserRole.fromApiValue('ACCOUNTANT'), UserRole.accountant);
    expect(UserRole.accountant.label, 'Accountant');
    expect(UserRole.accountant.administersSchool, isFalse);
  });

  test('every role the backend defines is known here', () {
    const backendRoles = [
      'SUPER_ADMIN',
      'GROUP_ADMIN',
      'SCHOOL_ADMIN',
      'HOD',
      'TEACHER',
      'STAFF',
      'TRANSPORT_MANAGER',
      'ACCOUNTANT',
    ];

    expect(UserRole.values.map((role) => role.apiValue), backendRoles);
  });
}
