import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/staff/data/models/attendant_access.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';

/// A Bus Attendant added without an email. Profile id and user id differ on
/// purpose, so a test can tell which one a form sent.
final meeraAttendant = StaffProfile(
  id: 31,
  userId: 131,
  employeeId: 'ATT-001',
  firstName: 'Meera',
  lastName: 'Sharma',
  name: 'Meera Sharma',
  email: 'attendant-1a2b3c4d5e6f7a8b@no-email.invalid',
  hasEmail: false,
  mobile: '+91 9876543210',
  role: UserRole.busAttendant,
  status: UserStatus.active,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: null,
  departmentName: null,
  designation: null,
  joiningDate: DateTime(2026, 9, 1),
  address: null,
  classTeacherOf: const [],
);

/// An attendant who has left - switched off, so never offered for a route.
final inactiveRaviAttendant = StaffProfile(
  id: 32,
  userId: 132,
  employeeId: 'ATT-002',
  firstName: 'Ravi',
  lastName: 'Das',
  name: 'Ravi Das',
  email: 'ravi@example.com',
  mobile: '+91 9123456780',
  role: UserRole.busAttendant,
  status: UserStatus.inactive,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: null,
  departmentName: null,
  designation: null,
  joiningDate: DateTime(2026, 9, 1),
  address: null,
  classTeacherOf: const [],
);

/// A teacher - never offered as a route's attendant.
final anitaTeacher = StaffProfile(
  id: 33,
  userId: 133,
  employeeId: 'TCH-050',
  firstName: 'Anita',
  lastName: 'Rao',
  name: 'Anita Rao',
  email: 'anita@example.com',
  mobile: null,
  role: UserRole.teacher,
  status: UserStatus.active,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: null,
  departmentName: null,
  designation: null,
  joiningDate: DateTime(2024, 6, 1),
  address: null,
  classTeacherOf: const [],
);

const redmiPhone = AttendantDevice(
  id: 7,
  name: 'Redmi Note 12',
  registeredAt: '2026-09-09T02:00:00.000000Z',
  lastUsedAt: '2026-09-10T01:45:00.000000Z',
  revokedAt: null,
  isActive: true,
);

const oldPhone = AttendantDevice(
  id: 6,
  name: 'Old Samsung',
  registeredAt: '2026-09-01T02:00:00.000000Z',
  lastUsedAt: null,
  revokedAt: '2026-09-05T02:00:00.000000Z',
  isActive: false,
);

/// Never set up: no passcode, no phone, no code waiting.
const freshAccess = AttendantAccess(
  loginMobile: '+919876543210',
  hasPasscode: false,
  isLocked: false,
  setupCodePending: false,
  setupCodeExpiresAt: null,
  devices: [],
);

/// Set up on one phone, with an older phone already removed.
const setUpAccess = AttendantAccess(
  loginMobile: '+919876543210',
  hasPasscode: true,
  isLocked: false,
  setupCodePending: false,
  setupCodeExpiresAt: null,
  devices: [redmiPhone, oldPhone],
);
