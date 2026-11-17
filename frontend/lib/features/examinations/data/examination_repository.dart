import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/examination.dart';

final examinationRepositoryProvider = Provider<ExaminationRepository>(
  (ref) => ExaminationRepository(ref.watch(dioClientProvider)),
);

/// Examinations and admit cards (docs/examinations.md). Every failure is the
/// app's [Failure], carrying the server's own sentence.
class ExaminationRepository {
  ExaminationRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(_readable(e));
    }
  }

  /// A PDF request's refusal arrives as bytes; turned back into the JSON the
  /// error envelope is, so the server's own sentence ("Withheld by the
  /// school.") reaches the screen rather than a generic one.
  static DioException _readable(DioException e) {
    final response = e.response;
    final data = response?.data;
    if (response == null || data is! List<int>) return e;

    try {
      final decoded = jsonDecode(utf8.decode(data));
      return e.copyWith(
        response: Response(
          requestOptions: response.requestOptions,
          statusCode: response.statusCode,
          headers: response.headers,
          data: decoded,
        ),
      );
    } on FormatException {
      return e;
    }
  }

  Future<PaginatedResponse<Examination>> list({int? academicYearId, int page = 1}) => _call(() async {
    final response = await _dio.get(
      '/examinations',
      queryParameters: {'academic_year_id': ?academicYearId, 'page': page},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Examination.fromJson);
  });

  Future<Examination> get(int id) => _call(() async {
    final response = await _dio.get('/examinations/$id');
    return Examination.fromJson(response.data as Map<String, dynamic>);
  });

  /// [fields] are the API's own names: academic_year_id (create only), name,
  /// academic_term_id, centre, reporting_time, instructions, card_style,
  /// block_on_fee_dues.
  Future<Examination> create(Map<String, dynamic> fields) => _call(() async {
    final response = await _dio.post('/examinations', data: fields);
    return Examination.fromJson(response.data as Map<String, dynamic>);
  });

  Future<Examination> update(int id, Map<String, dynamic> fields) => _call(() async {
    final response = await _dio.patch('/examinations/$id', data: fields);
    return Examination.fromJson(response.data as Map<String, dynamic>);
  });

  Future<void> delete(int id) => _call(() => _dio.delete('/examinations/$id'));

  /// Replaces the whole date sheet.
  Future<Examination> savePapers(int id, List<ExamPaper> papers) => _call(() async {
    final response = await _dio.put(
      '/examinations/$id/papers',
      data: {
        'papers': [for (final paper in papers) paper.toJson()],
      },
    );
    return Examination.fromJson(response.data as Map<String, dynamic>);
  });

  Future<Examination> publish(int id) => _call(() async {
    final response = await _dio.post('/examinations/$id/publish');
    return Examination.fromJson(response.data as Map<String, dynamic>);
  });

  Future<CandidatePage> candidates(int id, {int? sectionId, String? query, CardState? state, int page = 1}) =>
      _call(() async {
        final response = await _dio.get(
          '/examinations/$id/candidates',
          queryParameters: {
            'class_section_id': ?sectionId,
            if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
            'state': ?state?.apiValue,
            'page': page,
          },
        );
        final json = response.data as Map<String, dynamic>;
        final paged = PaginatedResponse.fromJson(json, ExamCandidate.fromJson);
        final counts = <CardState, int>{
          for (final entry in (json['counts'] as Map<String, dynamic>? ?? const {}).entries)
            CardState.fromApiValue(entry.key): entry.value as int,
        };
        return CandidatePage(
          items: paged.items,
          currentPage: paged.currentPage,
          lastPage: paged.lastPage,
          total: paged.total,
          counts: counts,
        );
      });

  /// [kind] is "withhold", "allow", or null to go back to the rules.
  Future<String> setException(int id, {required int studentId, String? kind, String? reason}) => _call(() async {
    final response = await _dio.put(
      '/examinations/$id/exceptions',
      data: {'student_id': studentId, 'kind': kind ?? 'none', 'reason': reason},
    );
    return (response.data as Map<String, dynamic>)['state'] as String;
  });

  /// One student's card. [draft] previews the unpublished sheet; [version]
  /// reprints an earlier issue.
  Future<List<int>> card(int id, int studentId, {bool draft = false, int? version}) => _call(() async {
    final response = await _dio.get<List<int>>(
      '/examinations/$id/students/$studentId/card.pdf',
      queryParameters: {if (draft) 'draft': 1, 'version': ?version},
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  });

  /// Every ready card of one section, one per sheet.
  Future<CardBatch> sectionCards(int id, {required int sectionId}) => _call(() async {
    final response = await _dio.get<List<int>>(
      '/examinations/$id/cards.pdf',
      queryParameters: {'class_section_id': sectionId},
      options: Options(responseType: ResponseType.bytes),
    );
    final disposition = response.headers.value('content-disposition') ?? '';
    final name = RegExp(r'filename="([^"]+)"').firstMatch(disposition)?.group(1) ?? 'admit-cards.pdf';
    return CardBatch(
      bytes: response.data ?? const [],
      fileName: name,
      printed: int.tryParse(response.headers.value('x-cards-printed') ?? '') ?? 0,
      skipped: int.tryParse(response.headers.value('x-cards-skipped') ?? '') ?? 0,
    );
  });
}
