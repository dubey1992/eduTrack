import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/dio_client.dart';
import 'import_api.dart';
import 'models/import_preview.dart';
import 'models/import_result.dart';

final importRepositoryProvider = Provider<ImportRepository>((ref) => ImportRepository(ref.watch(importApiProvider)));

/// A file the server refused, with the reason for every row that needs
/// fixing.
///
/// Separate from [Failure] because this is the one error the UI renders as a
/// table rather than as a sentence - the person is meant to work through it
/// with the spreadsheet open.
class BulkImportFailure implements Exception {
  const BulkImportFailure({required this.message, required this.rows});

  final String message;
  final List<ImportRowError> rows;
}

class ImportRepository {
  ImportRepository(this._api);

  final ImportApi _api;

  Future<List<int>> downloadTemplate(String type) async {
    try {
      return await _api.downloadTemplate(type);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<ImportResult> import({
    required String type,
    required String fileName,
    required List<int> bytes,
    int? schoolId,
  }) async {
    try {
      return await _api.import(type: type, fileName: fileName, bytes: bytes, schoolId: schoolId);
    } on DioException catch (e) {
      final failure = failureFromDioException(e);

      if (failure.code == 'BULK_IMPORT_FAILED') {
        throw BulkImportFailure(
          message: failure.message,
          rows: (failure.details['rows'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(ImportRowError.fromJson)
              .toList(growable: false),
        );
      }

      throw failure;
    }
  }

  /// A refused file throws [BulkImportFailure] here too, so the preview and
  /// the upload report the same rows in the same way.
  Future<ImportPreview> preview({
    required String type,
    required String fileName,
    required List<int> bytes,
    int? schoolId,
  }) async {
    try {
      return await _api.preview(type: type, fileName: fileName, bytes: bytes, schoolId: schoolId);
    } on DioException catch (e) {
      throw _refusalOf(e);
    }
  }

  Object _refusalOf(DioException error) {
    final failure = failureFromDioException(error);

    if (failure.code == 'BULK_IMPORT_FAILED') {
      return BulkImportFailure(
        message: failure.message,
        rows: (failure.details['rows'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ImportRowError.fromJson)
            .toList(growable: false),
      );
    }

    return failure;
  }
}
