import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/profile/data/models/profile.dart';
import 'package:edutrack_app/features/profile/data/profile_repository.dart';

/// Test double for [ProfileRepository] - keeps one [profile] the way the
/// server would and records what each call was asked for.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    Profile? profile,
    this.failGetWith,
    this.failUpdateWith,
    this.failEmailWith,
    this.failUploadWith,
    this.failRemoveWith,
  }) : profile = profile ?? teacherProfile();

  Profile profile;
  Failure? failGetWith;
  Failure? failUpdateWith;
  Failure? failEmailWith;
  Failure? failUploadWith;
  Failure? failRemoveWith;

  /// When set, [get] waits on it - so a test can look at the loading state.
  Completer<void>? getGate;

  int getCalls = 0;
  int updateCalls = 0;
  int removeCalls = 0;
  Map<String, String>? lastUpdate;
  ({String email, String currentPassword})? lastEmailChange;
  ({List<int> bytes, String fileName})? lastUpload;

  @override
  Future<Profile> get() async {
    getCalls++;
    if (getGate != null) await getGate!.future;
    if (failGetWith != null) throw failGetWith!;
    return profile;
  }

  @override
  Future<Profile> update(Map<String, String> changes) async {
    updateCalls++;
    lastUpdate = changes;
    if (failUpdateWith != null) throw failUpdateWith!;

    final firstName = changes['first_name'] ?? profile.firstName;
    final lastName = changes['last_name'] ?? profile.lastName;
    profile = _copy(
      firstName: firstName,
      lastName: lastName,
      name: '$firstName $lastName',
      mobile: changes.containsKey('mobile') ? _blankToNull(changes['mobile']) : profile.mobile,
      address: changes.containsKey('address') ? _blankToNull(changes['address']) : profile.address,
    );
    return profile;
  }

  @override
  Future<Profile> changeEmail({required String email, required String currentPassword}) async {
    lastEmailChange = (email: email, currentPassword: currentPassword);
    if (failEmailWith != null) throw failEmailWith!;

    profile = _copy(email: email);
    return profile;
  }

  @override
  Future<Profile> uploadPhoto({required List<int> bytes, required String fileName}) async {
    lastUpload = (bytes: bytes, fileName: fileName);
    if (failUploadWith != null) throw failUploadWith!;

    profile = _copy(photoUrl: '/users/${profile.id}/photo?v=new');
    return profile;
  }

  @override
  Future<Profile> removePhoto() async {
    removeCalls++;
    if (failRemoveWith != null) throw failRemoveWith!;

    profile = _copy(clearPhoto: true);
    return profile;
  }

  /// Marks a field [_copy] should leave as it is (null means "clear it").
  static const _keep = Object();

  static String? _blankToNull(String? value) => (value == null || value.isEmpty) ? null : value;

  Profile _copy({
    String? firstName,
    String? lastName,
    String? name,
    String? email,
    Object? mobile = _keep,
    Object? address = _keep,
    String? photoUrl,
    bool clearPhoto = false,
  }) {
    final p = profile;
    return Profile(
      id: p.id,
      firstName: firstName ?? p.firstName,
      lastName: lastName ?? p.lastName,
      name: name ?? p.name,
      email: email ?? p.email,
      mobile: identical(mobile, _keep) ? p.mobile : mobile as String?,
      role: p.role,
      roleLabel: p.roleLabel,
      schoolName: p.schoolName,
      photoUrl: clearPhoto ? null : (photoUrl ?? p.photoUrl),
      hasStaffRecord: p.hasStaffRecord,
      address: identical(address, _keep) ? p.address : address as String?,
      employment: p.employment,
      updatedAt: '2026-09-19T06:00:00Z',
      signsInWithPasscode: p.signsInWithPasscode,
    );
  }
}

/// A teacher with a staff record: address and work details included.
Profile teacherProfile({String? photoUrl, String? mobile = '+91 9876543210', String? address = '12 Lake Road'}) {
  return Profile(
    id: 12,
    firstName: 'Asha',
    lastName: 'Rao',
    name: 'Asha Rao',
    email: 'asha@example.com',
    mobile: mobile,
    role: 'TEACHER',
    roleLabel: 'Teacher',
    schoolName: 'Green Valley School',
    photoUrl: photoUrl,
    hasStaffRecord: true,
    address: address,
    employment: const Employment(
      employeeId: 'EMP-042',
      departmentName: 'Science',
      designation: 'Senior Teacher',
      joiningDate: '2024-06-01',
      joiningDateLabel: '01/06/2024',
    ),
    updatedAt: '2026-09-18T10:00:00Z',
  );
}

/// The platform owner: no school, no staff record, so no address or work card.
Profile superAdminProfile({String? photoUrl}) {
  return Profile(
    id: 1,
    firstName: 'Platform',
    lastName: 'Owner',
    name: 'Platform Owner',
    email: 'owner@example.com',
    mobile: null,
    role: 'SUPER_ADMIN',
    roleLabel: 'Super Admin',
    schoolName: null,
    photoUrl: photoUrl,
    hasStaffRecord: false,
    address: null,
    employment: null,
    updatedAt: '2026-09-18T10:00:00Z',
  );
}

/// A Bus Attendant added without an email: signs in with mobile and passcode.
Profile attendantProfile() {
  return const Profile(
    id: 31,
    firstName: 'Ravi',
    lastName: 'Kumar',
    name: 'Ravi Kumar',
    email: null,
    mobile: '+91 98765 43210',
    role: 'BUS_ATTENDANT',
    roleLabel: 'Bus Attendant',
    schoolName: 'Green Valley School',
    photoUrl: null,
    hasStaffRecord: true,
    address: null,
    employment: Employment(
      employeeId: 'ATT-01',
      departmentName: null,
      designation: 'Bus Attendant',
      joiningDate: '2026-04-01',
      joiningDateLabel: '04/01/2026',
    ),
    updatedAt: '2026-09-18T10:00:00Z',
    signsInWithPasscode: true,
  );
}
