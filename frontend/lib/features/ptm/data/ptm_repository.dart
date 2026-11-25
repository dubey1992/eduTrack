import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../../core/utils/date_format.dart';
import 'ptm_models.dart';

final ptmRepositoryProvider = Provider<PtmRepository>((ref) => PtmRepository(ref.watch(dioClientProvider)));

class PtmRepository {
  PtmRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<PtmMeeting>> list({required bool past, int page = 1}) => _call(() async {
    final response = await _dio.get('/ptm-meetings', queryParameters: {if (past) 'past': 1, 'page': page});
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, PtmMeeting.fromJson);
  });

  Future<PtmMeeting> get(int id) => _call(() async {
    final response = await _dio.get('/ptm-meetings/$id');
    return PtmMeeting.fromJson(response.data as Map<String, dynamic>);
  });

  Map<String, dynamic> _body(PtmMeetingDraft draft) => {
    'school_id': ?draft.schoolId,
    'title': draft.title,
    'meeting_date': apiDate(draft.date),
    'note': draft.note,
    'section_ids': draft.sectionIds,
  };

  Future<PtmMeeting> create(PtmMeetingDraft draft) => _call(() async {
    final response = await _dio.post('/ptm-meetings', data: _body(draft));
    return PtmMeeting.fromJson(response.data as Map<String, dynamic>);
  });

  Future<PtmMeeting> update(int id, PtmMeetingDraft draft) => _call(() async {
    final response = await _dio.patch('/ptm-meetings/$id', data: _body(draft));
    return PtmMeeting.fromJson(response.data as Map<String, dynamic>);
  });

  Future<PtmMeeting> cancel(int id) => _call(() async {
    final response = await _dio.post('/ptm-meetings/$id/cancel');
    return PtmMeeting.fromJson(response.data as Map<String, dynamic>);
  });

  Future<List<PtmSlot>> slots(int meetingId, int sectionId) => _call(() async {
    final response = await _dio.get('/ptm-meetings/$meetingId/sections/$sectionId/slots');
    return _slots(response.data);
  });

  /// Cuts [startsAt]-[endsAt] ("09:00") into [minutes]-long slots; answers
  /// with all of the class's slots.
  Future<List<PtmSlot>> openSlots(
    int meetingId,
    int sectionId, {
    required String startsAt,
    required String endsAt,
    required int minutes,
  }) => _call(() async {
    final response = await _dio.post(
      '/ptm-meetings/$meetingId/sections/$sectionId/slots',
      data: {'starts_at': startsAt, 'ends_at': endsAt, 'slot_minutes': minutes},
    );
    return _slots(response.data);
  });

  Future<void> removeSlot(int slotId) => _call(() => _dio.delete('/ptm-slots/$slotId'));

  static List<PtmSlot> _slots(dynamic data) => [
    for (final row in (data as Map<String, dynamic>)['data'] as List<dynamic>)
      PtmSlot.fromJson(row as Map<String, dynamic>),
  ];
}
