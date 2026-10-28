import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/company_details.dart';

final companyDetailsRepositoryProvider = Provider<CompanyDetailsRepository>(
  (ref) => CompanyDetailsRepository(ref.watch(dioClientProvider)),
);

/// School365ai's business details - Super Admin only. Failures become the
/// app's Failure, so the form shows the server's message and field errors.
class CompanyDetailsRepository {
  CompanyDetailsRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<CompanyDetails> get() => _call(() async {
    final response = await _dio.get('/settings/company');
    return CompanyDetails.fromJson(response.data as Map<String, dynamic>);
  });

  /// Saves every field; empty text clears one. The legal name is required.
  Future<CompanyDetails> save(Map<String, String> fields) => _call(() async {
    final response = await _dio.put('/settings/company', data: fields);
    return CompanyDetails.fromJson(response.data as Map<String, dynamic>);
  });
}
