import 'package:dio/dio.dart';
import 'package:edutrack_app/features/auth/data/attendant_auth_api.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';

/// The session payload an attendant signs in with: transport and leave to
/// manage, nothing else, and no real email on record.
Map<String, dynamic> attendantUserJson() => {
  'id': 9,
  'name': 'Asha Attendant',
  'email': 'attendant-9@no-email.invalid',
  'has_email': false,
  'role': 'BUS_ATTENDANT',
  'permissions': {
    for (final module in [
      'students',
      'staff',
      'academics',
      'attendance',
      'staff_attendance',
      'timetable',
      'teaching_reports',
      'syllabus',
      'hod',
      'communication',
      'announcements',
      'payroll',
      'reports',
    ])
      module: 'none',
    'transport': 'manage',
    'leave': 'manage',
  },
  'modules': <String, bool>{},
};

/// The attendant sign-in endpoints, answered from memory.
class FakeAttendantAuthApi implements AttendantAuthApi {
  /// When set, the next call throws this instead of signing in.
  DioException? error;

  final List<Map<String, String>> setupCalls = [];
  final List<Map<String, String>> loginCalls = [];

  @override
  Future<AttendantSignIn> setup({
    required String mobile,
    required String setupCode,
    required String passcode,
    required String deviceName,
  }) async {
    setupCalls.add({'mobile': mobile, 'setup_code': setupCode, 'passcode': passcode});
    if (error != null) throw error!;

    return _signIn(deviceSecret: 'secret-from-the-server');
  }

  @override
  Future<AttendantSignIn> login({
    required String mobile,
    required String passcode,
    required String deviceSecret,
  }) async {
    loginCalls.add({'mobile': mobile, 'passcode': passcode, 'device_secret': deviceSecret});
    if (error != null) throw error!;

    return _signIn();
  }

  AttendantSignIn _signIn({String? deviceSecret}) {
    final json = attendantUserJson();
    return AttendantSignIn(
      user: AuthenticatedUser.fromJson(json),
      userJson: json,
      token: 'attendant-token',
      deviceSecret: deviceSecret,
    );
  }
}
