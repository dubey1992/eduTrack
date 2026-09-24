import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/import_preview.dart';
import 'models/import_result.dart';

final importApiProvider = Provider<ImportApi>((ref) => ImportApi(ref.watch(dioClientProvider)));

/// The two bulk-upload endpoints. The kind of record is a path segment, so
/// one pair covers students, staff, subjects, vehicles and drivers alike.
class ImportApi {
  ImportApi(this._dio);

  final Dio _dio;

  /// The empty spreadsheet, fetched through the authenticated client rather
  /// than by opening a URL - a token does not belong in a link.
  Future<List<int>> downloadTemplate(String type) async {
    final response = await _dio.get<List<int>>(
      '/imports/$type/template',
      options: Options(responseType: ResponseType.bytes),
    );

    return response.data ?? const [];
  }

  Future<ImportResult> import({
    required String type,
    required String fileName,
    required List<int> bytes,
    int? schoolId,
  }) async {
    final fields = <String, dynamic>{'file': MultipartFile.fromBytes(bytes, filename: fileName)};

    // Only a Super Admin sends this, and only they may: for everybody else
    // the school comes from the account, server-side.
    if (schoolId != null) fields['school_id'] = schoolId;

    final form = FormData.fromMap(fields);

    final response = await _dio.post('/imports/$type', data: form);

    return ImportResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// What the file would import. Nothing is written.
  Future<ImportPreview> preview({
    required String type,
    required String fileName,
    required List<int> bytes,
    int? schoolId,
  }) async {
    final fields = <String, dynamic>{'file': MultipartFile.fromBytes(bytes, filename: fileName)};

    if (schoolId != null) fields['school_id'] = schoolId;

    final response = await _dio.post('/imports/$type/preview', data: FormData.fromMap(fields));

    return ImportPreview.fromJson(response.data as Map<String, dynamic>);
  }
}
