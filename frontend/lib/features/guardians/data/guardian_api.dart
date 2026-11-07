import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/guardian_link.dart';

final guardianApiProvider = Provider<GuardianApi>((ref) => GuardianApi(ref.watch(dioClientProvider)));

/// A student's guardians and their Family app sign-in
/// (docs/parent-student-app.md, F0).
class GuardianApi {
  GuardianApi(this._dio);

  final Dio _dio;

  String _base(int studentId) => '/students/$studentId/guardians';

  Future<List<GuardianLink>> list(int studentId) async {
    final response = await _dio.get(_base(studentId));
    return [
      for (final row in response.data['data'] as List<dynamic>) GuardianLink.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<GuardianLink> add(int studentId, Map<String, dynamic> fields) async {
    final response = await _dio.post(_base(studentId), data: fields);
    return GuardianLink.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<GuardianLink> update(int studentId, int linkId, Map<String, dynamic> fields) async {
    final response = await _dio.patch('${_base(studentId)}/$linkId', data: fields);
    return GuardianLink.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> unlink(int studentId, int linkId) => _dio.delete('${_base(studentId)}/$linkId');

  Future<FamilyAccess> access(int studentId, int linkId) async {
    final response = await _dio.get('${_base(studentId)}/$linkId/family-access');
    return FamilyAccess.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<IssuedSetupCode> issueSetupCode(int studentId, int linkId, {required bool consent}) async {
    final response = await _dio.post(
      '${_base(studentId)}/$linkId/family-access/setup-code',
      data: {'consent': consent},
    );
    return IssuedSetupCode.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  /// The parent's letter, with a fresh setup code printed on it. Fetched
  /// through the signed-in client: the code never travels in a link.
  Future<List<int>> letter(int studentId, int linkId, {required bool consent}) async {
    final response = await _dio.post<List<int>>(
      '${_base(studentId)}/$linkId/family-access/letter',
      data: {'consent': consent},
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }

  Future<FamilyAccess> removePhone(int studentId, int linkId, int deviceId) async {
    final response = await _dio.delete('${_base(studentId)}/$linkId/family-access/devices/$deviceId');
    return FamilyAccess.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}
