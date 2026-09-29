import 'package:dio/dio.dart';
import 'package:edutrack_app/features/imports/data/import_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// One pair of endpoints covers every kind of record, so the thing worth
/// holding on to is that each screen's own kind reaches its own path. The
/// Students screen must not check a file against the vehicles rules.
class _Recorder {
  final List<String> paths = [];
  Map<String, dynamic> answer = const {
    'label': 'Students',
    'headings': ['admission_number'],
    'row_count': 1,
    'rows': [
      {
        'row': 2,
        'values': ['ADM-1'],
      },
    ],
    'truncated': false,
  };
  FormData? sent;

  Dio dio() {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          paths.add(options.path);
          if (options.data is FormData) sent = options.data as FormData;
          handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: answer));
        },
      ),
    );

    return dio;
  }
}

/// Every kind of record the bulk upload offers, as the API path spells it.
const kinds = ['students', 'staff', 'subjects', 'vehicles', 'drivers', 'assessments'];

void main() {
  group('checking a file before importing it', () {
    test('asks about the kind of record the screen is showing', () async {
      final recorder = _Recorder();
      final api = ImportApi(recorder.dio());

      for (final kind in kinds) {
        await api.preview(type: kind, fileName: 'upload.csv', bytes: const [1, 2, 3]);
      }

      expect(recorder.paths, [for (final kind in kinds) '/imports/$kind/preview']);
    });

    test('sends the file itself, under the name the server reads', () async {
      final recorder = _Recorder();

      await ImportApi(recorder.dio()).preview(type: 'staff', fileName: 'teachers.csv', bytes: const [1, 2, 3]);

      final fields = recorder.sent!.files.map((entry) => entry.key).toList();
      expect(fields, ['file']);
      expect(recorder.sent!.files.single.value.filename, 'teachers.csv');
    });

    test('a school is named only by somebody who has to name one', () async {
      final recorder = _Recorder();
      final api = ImportApi(recorder.dio());

      await api.preview(type: 'students', fileName: 'upload.csv', bytes: const [1], schoolId: 4);
      final named = recorder.sent!.fields;
      expect(named.map((entry) => '${entry.key}=${entry.value}'), ['school_id=4']);

      await api.preview(type: 'students', fileName: 'upload.csv', bytes: const [1]);
      expect(recorder.sent!.fields, isEmpty, reason: 'a school admin imports into their own school, server-side');
    });

    test('reads back what the file would import', () async {
      final recorder = _Recorder();

      final preview = await ImportApi(recorder.dio())
          .preview(type: 'vehicles', fileName: 'vehicles.csv', bytes: const [1]);

      expect(preview.rowCount, 1);
      expect(preview.rows.single.values, ['ADM-1']);
    });

    test('importing goes to the path without the preview step', () async {
      final recorder = _Recorder();
      recorder.answer = const {'imported': 2, 'label': 'Drivers'};

      final result = await ImportApi(recorder.dio()).import(type: 'drivers', fileName: 'd.csv', bytes: const [1]);

      expect(recorder.paths, ['/imports/drivers']);
      expect(result.imported, 2);
    });
  });
}
