import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/dio_client.dart';
import 'models/photo_import.dart';
import 'student_photo_import_api.dart';

final studentPhotoImportRepositoryProvider = Provider<StudentPhotoImportRepository>(
  (ref) => StudentPhotoImportRepository(ref.watch(studentPhotoImportApiProvider)),
);

/// Student photos in bulk (docs/student-photos.md, P2), with the server's
/// errors turned into [Failure]s.
class StudentPhotoImportRepository {
  StudentPhotoImportRepository(this._api);

  final StudentPhotoImportApi _api;

  Future<List<PhotoPreviewRow>> preview(List<String> fileNames, {int? schoolId}) async {
    try {
      return await _api.preview(fileNames, schoolId: schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<List<PhotoUploadResult>> upload(List<({String name, List<int> bytes})> files, {int? schoolId}) async {
    try {
      return await _api.upload(files, schoolId: schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}
