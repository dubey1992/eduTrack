import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'guardian_api.dart';
import 'models/guardian_link.dart';

final guardianRepositoryProvider = Provider<GuardianRepository>(
  (ref) => GuardianRepository(ref.watch(guardianApiProvider)),
);

/// The guardians API, with every failure turned into the app's [Failure].
class GuardianRepository {
  GuardianRepository(this._api);

  final GuardianApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<List<GuardianLink>> list(int studentId) => _call(() => _api.list(studentId));

  Future<GuardianLink> add(
    int studentId, {
    required String name,
    String? mobile,
    String? email,
    required GuardianRelationship relationship,
    required bool isPrimary,
  }) {
    return _call(
      () => _api.add(studentId, {
        'name': name,
        'mobile': mobile,
        'email': email,
        'relationship': relationship.apiValue,
        'is_primary': isPrimary,
      }),
    );
  }

  Future<GuardianLink> update(
    int studentId,
    int linkId, {
    required String name,
    String? mobile,
    String? email,
    required GuardianRelationship relationship,
    required bool isPrimary,
  }) {
    return _call(
      () => _api.update(studentId, linkId, {
        'name': name,
        'mobile': mobile,
        'email': email,
        'relationship': relationship.apiValue,
        // Only ever sets primary: the other guardian becoming primary is how
        // this one stops being it.
        if (isPrimary) 'is_primary': true,
      }),
    );
  }

  Future<void> unlink(int studentId, int linkId) => _call(() => _api.unlink(studentId, linkId));

  Future<FamilyAccess> access(int studentId, int linkId) => _call(() => _api.access(studentId, linkId));

  Future<IssuedSetupCode> issueSetupCode(int studentId, int linkId, {required bool consent}) =>
      _call(() => _api.issueSetupCode(studentId, linkId, consent: consent));

  Future<List<int>> letter(int studentId, int linkId, {required bool consent}) =>
      _call(() => _api.letter(studentId, linkId, consent: consent));

  Future<FamilyAccess> removePhone(int studentId, int linkId, int deviceId) =>
      _call(() => _api.removePhone(studentId, linkId, deviceId));
}
