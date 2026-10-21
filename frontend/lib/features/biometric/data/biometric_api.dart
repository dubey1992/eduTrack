import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/biometric_device.dart';
import 'models/biometric_punch.dart';

final biometricApiProvider = Provider<BiometricApi>((ref) => BiometricApi(ref.watch(dioClientProvider)));

class BiometricApi {
  BiometricApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<BiometricDevice>> listDevices({
    int? schoolId,
    int? page,
    int? perPage,
    String? q,
    String? status,
  }) async {
    final response = await _dio.get(
      '/biometric/devices',
      queryParameters: {'school_id': ?schoolId, 'page': ?page, 'per_page': ?perPage, 'q': ?q, 'status': ?status},
    );

    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, BiometricDevice.fromJson);
  }

  Future<BiometricDevice> createDevice(Map<String, dynamic> body) async {
    final response = await _dio.post('/biometric/devices', data: body);

    return BiometricDevice.fromJson(response.data as Map<String, dynamic>);
  }

  Future<BiometricDevice> updateDevice(int deviceId, Map<String, dynamic> body) async {
    final response = await _dio.patch('/biometric/devices/$deviceId', data: body);

    return BiometricDevice.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteDevice(int deviceId) async {
    await _dio.delete('/biometric/devices/$deviceId');
  }

  Future<PunchPage> listPunches({
    int? schoolId,
    int? page,
    int? perPage,
    String? q,
    String? date,
    bool unmatchedOnly = false,
  }) async {
    final response = await _dio.get(
      '/biometric/punches',
      queryParameters: {
        'school_id': ?schoolId,
        'page': ?page,
        'per_page': ?perPage,
        'q': ?q,
        'date': ?date,
        if (unmatchedOnly) 'unmatched': '1',
      },
    );

    return PunchPage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PunchUploadResult> uploadPunches({required String fileName, required List<int> bytes, int? schoolId}) async {
    final fields = <String, dynamic>{'file': MultipartFile.fromBytes(bytes, filename: fileName)};

    // Only somebody who picks a school sends this, and only they may: for
    // everybody else the school comes from the account, server-side.
    if (schoolId != null) fields['school_id'] = schoolId;

    final response = await _dio.post('/biometric/punches/upload', data: FormData.fromMap(fields));

    return PunchUploadResult.fromJson(response.data as Map<String, dynamic>);
  }
}
