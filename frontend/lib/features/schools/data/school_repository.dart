import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/school.dart';
import 'models/timezone_option.dart';
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

  /// The zones a school can be set to. Comes from the server so the picker
  /// can never offer one the backend would reject.
  Future<List<TimezoneOption>> listTimezones() async {
    try {
      return await _api.listTimezones();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<School> create({
    required String name,
    int? parentSchoolId,
    String? registrationNumber,
    required String email,
    required String phone,
    required String address,
    required String city,
    required String state,
    required String country,
    required String postalCode,
    required String currencyCode,
    required String timezone,
    String? latitude,
    String? longitude,
  }) async {
    try {
      return await _api.create({
        'name': name,
        'parent_school_id': parentSchoolId,
        'registration_number': registrationNumber,
        'email': email,
        'phone': phone,
        'address': address,
        'city': city,
        'state': state,
        'country': country,
        'postal_code': postalCode,
        'currency_code': currencyCode,
        'timezone': timezone,
        'latitude': latitude,
        'longitude': longitude,
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
    String? timezone,
    String? latitude,
    String? longitude,
    // Sent only when the caller means to change it: a plain edit must not
    // silently pull a branch out of its group.
    bool changeParent = false,
    int? parentSchoolId,
  }) async {
    try {
      return await _api.update(schoolId, {
        if (changeParent) 'parent_school_id': parentSchoolId,
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
        'timezone': ?timezone,
        // Sent even when empty, so clearing a coordinate actually clears it.
        'latitude': latitude,
        'longitude': longitude,
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
