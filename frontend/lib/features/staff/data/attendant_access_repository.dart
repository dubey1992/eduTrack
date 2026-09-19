import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/attendant_access.dart';
import 'staff_api.dart';

final attendantAccessRepositoryProvider = Provider<AttendantAccessRepository>(
  (ref) => AttendantAccessRepository(ref.watch(staffApiProvider)),
);

/// A Bus Attendant's sign-in, managed from their staff record: setup codes
/// and registered phones. Unlocking after five wrong passcodes is the
/// ordinary user unlock (UserRepository.unlock), not repeated here.
class AttendantAccessRepository {
  AttendantAccessRepository(this._api);

  final StaffApi _api;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AttendantAccess> get(int staffProfileId) => _guard(() => _api.attendantAccess(staffProfileId));

  Future<AttendantSetupCode> issueSetupCode(int staffProfileId) => _guard(() => _api.issueSetupCode(staffProfileId));

  Future<AttendantAccess> removeDevice(int staffProfileId, int deviceId) =>
      _guard(() => _api.removeAttendantDevice(staffProfileId, deviceId));
}
