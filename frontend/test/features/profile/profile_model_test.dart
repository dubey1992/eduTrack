import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/profile/data/models/profile.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _profileJson({Object? employment}) => {
  'id': 12,
  'first_name': 'Asha',
  'last_name': 'Rao',
  'name': 'Asha Rao',
  'email': 'asha@example.com',
  'mobile': null,
  'role': 'TEACHER',
  'role_label': 'Teacher',
  'school_name': 'Green Valley School',
  'photo_url': '/users/12/photo?v=ab12',
  'has_staff_record': true,
  'address': '12 Lake Road',
  'employment': employment,
  'updated_at': '2026-09-18T10:00:00Z',
};

/// The payloads the profile feature reads, and the photo_url every user
/// payload now carries.
void main() {
  test('a profile parses with its work details', () {
    final profile = Profile.fromJson(
      _profileJson(
        employment: {
          'employee_id': 'EMP-042',
          'department_name': null,
          'designation': 'Senior Teacher',
          'joining_date': '2024-06-01',
          'joining_date_label': '01/06/2024',
        },
      ),
    );

    expect(profile.name, 'Asha Rao');
    expect(profile.mobile, isNull);
    expect(profile.photoUrl, '/users/12/photo?v=ab12');
    expect(profile.hasStaffRecord, isTrue);
    expect(profile.employment!.employeeId, 'EMP-042');
    expect(profile.employment!.departmentName, isNull);
    expect(profile.employment!.joiningDateLabel, '01/06/2024');
  });

  test('a profile without a staff record has no work details', () {
    expect(Profile.fromJson(_profileJson()).employment, isNull);
  });

  test('the session, admin-user and staff payloads carry photo_url', () {
    final session = AuthenticatedUser.fromJson({
      'id': 1,
      'name': 'Asha Rao',
      'email': 'asha@example.com',
      'role': 'TEACHER',
      'photo_url': '/users/1/photo?v=1',
    });
    final user = AppUser.fromJson({
      'id': 1,
      'first_name': 'Asha',
      'last_name': 'Rao',
      'name': 'Asha Rao',
      'email': 'asha@example.com',
      'mobile': null,
      'role': 'TEACHER',
      'status': 'active',
      'photo_url': '/users/1/photo?v=1',
    });
    final staff = StaffProfile.fromJson({
      'id': 5,
      'user_id': 1,
      'employee_id': 'EMP-042',
      'first_name': 'Asha',
      'last_name': 'Rao',
      'name': 'Asha Rao',
      'email': 'asha@example.com',
      'mobile': null,
      'role': 'TEACHER',
      'status': 'active',
      'school_id': 1,
      'school_name': null,
      'department_id': null,
      'department_name': null,
      'designation': null,
      'joining_date': '2024-06-01',
      'address': null,
      'class_teacher_of': <String>[],
      'photo_url': '/users/1/photo?v=1',
    });

    expect(session.photoUrl, '/users/1/photo?v=1');
    expect(user.photoUrl, '/users/1/photo?v=1');
    expect(staff.photoUrl, '/users/1/photo?v=1');
    // The copies the lists make keep it.
    expect(user.copyWith(unlocked: true).photoUrl, '/users/1/photo?v=1');
    expect(staff.copyWith(designation: 'HOD').photoUrl, '/users/1/photo?v=1');
  });

  test('a payload without photo_url means no photo', () {
    final session = AuthenticatedUser.fromJson({'id': 1, 'name': 'A', 'email': 'a@example.com', 'role': 'TEACHER'});
    expect(session.photoUrl, isNull);
  });
}
