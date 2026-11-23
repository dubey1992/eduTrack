import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/photo_import.dart';

final studentPhotoImportApiProvider = Provider<StudentPhotoImportApi>(
  (ref) => StudentPhotoImportApi(ref.watch(dioClientProvider)),
);

/// The two bulk photo endpoints (docs/student-photos.md, P2).
///
/// [schoolId] is sent only by somebody who has to say which school - a
/// Super Admin; for everybody else the server uses their own school.
class StudentPhotoImportApi {
  StudentPhotoImportApi(this._dio);

  final Dio _dio;

  /// What each file would do, judged from its name alone.
  Future<List<PhotoPreviewRow>> preview(List<String> fileNames, {int? schoolId}) async {
    final response = await _dio.post(
      '/imports/student-photos/preview',
      data: {'file_names': fileNames, 'school_id': ?schoolId},
    );
    final rows = (response.data as Map<String, dynamic>)['rows'] as List;

    return [for (final row in rows) PhotoPreviewRow.fromJson(row as Map<String, dynamic>)];
  }

  /// One batch - at most ten files. Each file gets its own result.
  Future<List<PhotoUploadResult>> upload(List<({String name, List<int> bytes})> files, {int? schoolId}) async {
    final form = FormData();
    for (final file in files) {
      form.files.add(MapEntry('photos', MultipartFile.fromBytes(file.bytes, filename: file.name)));
    }
    if (schoolId != null) form.fields.add(MapEntry('school_id', '$schoolId'));

    final response = await _dio.post('/imports/student-photos', data: form);
    final results = (response.data as Map<String, dynamic>)['results'] as List;

    return [for (final result in results) PhotoUploadResult.fromJson(result as Map<String, dynamic>)];
  }
}
