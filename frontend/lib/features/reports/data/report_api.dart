import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/report.dart';

final reportApiProvider = Provider<ReportApi>((ref) => ReportApi(ref.watch(dioClientProvider)));

class ReportApi {
  ReportApi(this._dio);

  final Dio _dio;

  Future<ReportResult> fetch(
    ReportKind kind, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    final response = await _dio.get(
      '/reports/${kind.apiPath}',
      queryParameters: _params(schoolId, from, to, classSectionId, departmentId),
    );

    return ReportResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// The same figures as CSV bytes, fetched through the authenticated client
  /// rather than by opening a URL - a token does not belong in a link.
  Future<List<int>> downloadCsv(
    ReportKind kind, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    final response = await _dio.get<List<int>>(
      '/reports/${kind.apiPath}',
      queryParameters: {..._params(schoolId, from, to, classSectionId, departmentId), 'format': 'csv'},
      options: Options(responseType: ResponseType.bytes),
    );

    return response.data ?? const [];
  }

  Map<String, dynamic> _params(int? schoolId, String? from, String? to, int? sectionId, int? departmentId) {
    return {
      'school_id': ?schoolId,
      'from': ?from,
      'to': ?to,
      'class_section_id': ?sectionId,
      'department_id': ?departmentId,
    };
  }
}
