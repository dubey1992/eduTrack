import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_response.dart';
import '../../../core/network/dio_client.dart';
import 'biometric_api.dart';
import 'models/biometric_device.dart';
import 'models/biometric_punch.dart';

final biometricRepositoryProvider = Provider<BiometricRepository>(
  (ref) => BiometricRepository(ref.watch(biometricApiProvider)),
);

class BiometricRepository {
  BiometricRepository(this._api);

  final BiometricApi _api;

  Future<PaginatedResponse<BiometricDevice>> listDevices({
    int? schoolId,
    required int page,
    required int perPage,
    String? q,
    String? status,
  }) async {
    try {
      return await _api.listDevices(schoolId: schoolId, page: page, perPage: perPage, q: q, status: status);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<BiometricDevice> createDevice({
    int? schoolId,
    required String name,
    required String serialNumber,
    String? location,
    String? pushKey,
  }) async {
    try {
      return await _api.createDevice({
        'school_id': schoolId,
        'name': name,
        'serial_number': serialNumber,
        'location': location,
        'push_key': pushKey,
      });
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<BiometricDevice> updateDevice(
    int deviceId, {
    String? name,
    String? serialNumber,
    String? location,
    String? pushKey,
  }) async {
    try {
      return await _api.updateDevice(deviceId, {
        'name': ?name,
        'serial_number': ?serialNumber,
        // Sent even when empty, so clearing a location actually clears it.
        'location': location,
        // Left out entirely when untouched: the server never sends the key
        // back, so an empty string here would mean "clear it" rather than
        // "leave it alone" (docs/biometric.md, B4).
        'push_key': ?pushKey,
      });
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<void> deleteDevice(int deviceId) async {
    try {
      await _api.deleteDevice(deviceId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PunchPage> listPunches({
    int? schoolId,
    required int page,
    required int perPage,
    String? q,
    String? date,
    bool unmatchedOnly = false,
  }) async {
    try {
      return await _api.listPunches(
        schoolId: schoolId,
        page: page,
        perPage: perPage,
        q: q,
        date: date,
        unmatchedOnly: unmatchedOnly,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PunchUploadResult> uploadPunches({required String fileName, required List<int> bytes, int? schoolId}) async {
    try {
      return await _api.uploadPunches(fileName: fileName, bytes: bytes, schoolId: schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
