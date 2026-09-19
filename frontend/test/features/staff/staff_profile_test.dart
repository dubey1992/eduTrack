import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/staff/data/models/attendant_access.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({Object? hasEmail = _absent, String role = 'BUS_ATTENDANT'}) {
  return {
    'id': 31,
    'user_id': 131,
    'employee_id': 'ATT-001',
    'first_name': 'Meera',
    'last_name': 'Sharma',
    'name': 'Meera Sharma',
    'email': 'attendant-1a2b@no-email.invalid',
    'mobile': '+91 9876543210',
    'role': role,
    'status': 'active',
    'locked_until': null,
    'photo_url': null,
    if (hasEmail != _absent) 'has_email': hasEmail,
    'school_id': 1,
    'school_name': 'Sunrise Public School',
    'department_id': null,
    'department_name': null,
    'designation': null,
    'joining_date': '2026-09-01',
    'address': null,
    'class_teacher_of': <String>[],
  };
}

const _absent = Object();

void main() {
  test('a Bus Attendant without an email parses with hasEmail false', () {
    final profile = StaffProfile.fromJson(_json(hasEmail: false));

    expect(profile.role, UserRole.busAttendant);
    expect(profile.isBusAttendant, isTrue);
    expect(profile.hasEmail, isFalse);
    // Carried through copies, so an unlock or a status change keeps it.
    expect(profile.copyWith(status: UserStatus.inactive).hasEmail, isFalse);
  });

  test('an older payload without has_email is taken to have one', () {
    final profile = StaffProfile.fromJson(_json(role: 'TEACHER'));

    expect(profile.hasEmail, isTrue);
    expect(profile.isBusAttendant, isFalse);
  });

  test('the attendant sign-in parses, devices included', () {
    final access = AttendantAccess.fromJson({
      'login_mobile': '+919876543210',
      'has_passcode': true,
      'is_locked': false,
      'setup_code_pending': true,
      'setup_code_expires_at': '2026-09-11T02:00:00Z',
      'devices': [
        {
          'id': 7,
          'name': null,
          'registered_at': '2026-09-09T02:00:00Z',
          'last_used_at': null,
          'revoked_at': null,
          'is_active': true,
        },
      ],
    });

    expect(access.setupCodePending, isTrue);
    expect(access.devices.single.displayName, 'Unnamed phone');
    expect(access.devices.single.isActive, isTrue);
  });
}
