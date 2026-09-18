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
    bool compare = false,
    int? below,
  }) async {
    final response = await _dio.get(
      '/reports/${kind.apiPath}',
      queryParameters: _params(schoolId, from, to, classSectionId, departmentId, compare, below),
    );

    return ReportResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// The same figures as a file, fetched through the authenticated client
  /// rather than by opening a URL - a token does not belong in a link.
  Future<List<int>> download(
    ReportKind kind,
    ExportFormat format, {
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
    bool compare = false,
    int? below,
  }) async {
    final response = await _dio.get<List<int>>(
      '/reports/${kind.apiPath}',
      queryParameters: {
        ..._params(schoolId, from, to, classSectionId, departmentId, compare, below),
        'format': format.apiValue,
      },
      options: Options(responseType: ResponseType.bytes),
    );

    return response.data ?? const [];
  }

  Map<String, dynamic> _params(
    int? schoolId,
    String? from,
    String? to,
    int? sectionId,
    int? departmentId,
    bool compare,
    int? below,
  ) {
    return {
      'school_id': ?schoolId,
      'from': ?from,
      'to': ?to,
      'class_section_id': ?sectionId,
      'department_id': ?departmentId,
      // Left out rather than sent as 0, so a plain report is asked for
      // exactly as it always was.
      if (compare) 'compare': 1,
      'below': ?below,
    };
  }
}
