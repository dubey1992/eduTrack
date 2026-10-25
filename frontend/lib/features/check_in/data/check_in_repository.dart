import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../my_trip/data/location_source.dart';
import 'models/my_attendance_day.dart';

final checkInApiProvider = Provider<CheckInApi>((ref) => CheckInApi(ref.watch(dioClientProvider)));

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(ref.watch(checkInApiProvider)),
);

/// The caller's own staff-register endpoints. None takes a person or a
/// school: the server marks whoever is signed in, in their own school.
class CheckInApi {
  CheckInApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> today() async {
    final response = await _dio.get('/staff-attendance/me');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkIn(DevicePosition at) => _post('/staff-attendance/me/check-in', at);

  Future<Map<String, dynamic>> checkOut(DevicePosition at) => _post('/staff-attendance/me/check-out', at);

  Future<Map<String, dynamic>> _post(String path, DevicePosition at) async {
    final response = await _dio.post(
      path,
      data: {
        'latitude': at.latitude,
        'longitude': at.longitude,
        'accuracy_m': at.accuracy,
        // The server refuses a made-up or remembered position; it can only
        // do that if it is told (school/check_in.py).
        'is_mocked': at.isMocked,
        if (at.takenAt != null) 'fix_age_s': DateTime.now().difference(at.takenAt!).inMilliseconds.abs() / 1000,
      },
    );
    return response.data as Map<String, dynamic>;
  }
}

class CheckInRepository {
  CheckInRepository(this._api);

  final CheckInApi _api;

  Future<MyAttendanceDay> today() => _guard(_api.today);

  Future<MyAttendanceDay> checkIn(DevicePosition at) => _guard(() => _api.checkIn(at));

  Future<MyAttendanceDay> checkOut(DevicePosition at) => _guard(() => _api.checkOut(at));

  Future<MyAttendanceDay> _guard(Future<Map<String, dynamic>> Function() call) async {
    try {
      return MyAttendanceDay.fromJson(await call());
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
