import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/school.dart';
import 'school_api.dart';

final schoolRepositoryProvider = Provider<SchoolRepository>((ref) => SchoolRepository(ref.watch(schoolApiProvider)));

class SchoolRepository {
  SchoolRepository(this._api);

  final SchoolApi _api;

  Future<List<School>> list() async {
    try {
      final page = await _api.list();
      return page.items;
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<School>> listPage({required int page, required int perPage}) async {
    try {
      return await _api.list(page: page, perPage: perPage);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<School> create({
    required String name,
    String? registrationNumber,
    required String email,
    required String phone,
    required String address,
    required String city,
    required String state,
    required String country,
    required String postalCode,
    required String currencyCode,
  }) async {
    try {
      return await _api.create({
        'name': name,
        'registration_number': registrationNumber,
        'email': email,
        'phone': phone,
        'address': address,
        'city': city,
        'state': state,
        'country': country,
        'postal_code': postalCode,
        'currency_code': currencyCode,
      });
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<School> update(
    int schoolId, {
    String? name,
    String? registrationNumber,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? currencyCode,
  }) async {
    try {
      return await _api.update(schoolId, {
        'name': ?name,
        'registration_number': registrationNumber,
        'email': ?email,
        'phone': ?phone,
        'address': ?address,
        'city': ?city,
        'state': ?state,
        'country': ?country,
        'postal_code': ?postalCode,
        'currency_code': ?currencyCode,
      });
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<School> setActive(int schoolId, bool active) async {
    try {
      return active ? await _api.activate(schoolId) : await _api.deactivate(schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
