import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';

/// What the server says after a logo is uploaded or removed.
class SchoolLogoResult {
  const SchoolLogoResult({required this.logoUrl, required this.profileComplete});

  factory SchoolLogoResult.fromJson(Map<String, dynamic> json) => SchoolLogoResult(
    logoUrl: json['logo_url'] as String?,
    profileComplete: json['profile_complete'] as bool? ?? false,
  );

  /// Where the new logo is served, or null once it is removed.
  final String? logoUrl;
  final bool profileComplete;
}

final schoolLogoRepositoryProvider = Provider<SchoolLogoRepository>(
  (ref) => SchoolLogoRepository(ref.watch(dioClientProvider)),
);

/// A school's logo (docs/school-logo.md). The server decides who may change
/// it; the school id only says which school is meant.
class SchoolLogoRepository {
  SchoolLogoRepository(this._dio);

  final Dio _dio;

  Future<SchoolLogoResult> upload({required int schoolId, required List<int> bytes, required String fileName}) {
    return _call(() {
      final form = FormData.fromMap({'logo': MultipartFile.fromBytes(bytes, filename: fileName)});
      return _dio.post('/schools/$schoolId/logo', data: form);
    });
  }

  Future<SchoolLogoResult> remove(int schoolId) => _call(() => _dio.delete('/schools/$schoolId/logo'));

  Future<SchoolLogoResult> _call(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return SchoolLogoResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
