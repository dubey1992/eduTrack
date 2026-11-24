import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../application/family_offline.dart';
import 'family_saved_copies.dart';
import 'models/family_admit_card.dart';
import 'models/family_absence_note.dart';
import 'models/family_bus.dart';
import 'models/family_call_request.dart';
import 'models/family_fees.dart';
import 'models/family_learning.dart';
import 'models/family_homework.dart';
import 'models/family_records.dart';

final familyApiProvider = Provider<FamilyApi>(
  (ref) => FamilyApi(
    ref.watch(dioClientProvider),
    copies: ref.watch(familySavedCopiesProvider),
    onAnswer: (name, savedAt) {
      final offline = ref.read(familyOfflineProvider.notifier);
      savedAt == null ? offline.fresh(name) : offline.old(name, savedAt);
    },
  ),
);

/// Says whether a screen's answer came from the server (null) or is the
/// copy saved on the phone at [savedAt].
typedef OnAnswer = void Function(String name, DateTime? savedAt);

/// The parent's screens' endpoints (school/views/family.py). Just HTTP - and
/// each screen's last answer kept on the phone for when there is no signal
/// (docs/mobile-apps-review.md, 2.2).
class FamilyApi {
  FamilyApi(this._dio, {this.copies, this.onAnswer});

  final Dio _dio;
  final FamilySavedCopies? copies;
  final OnAnswer? onAnswer;

  /// GET [path], saving the answer as [name]; with no signal at all, the
  /// copy saved last time - or the failure, when there is none.
  Future<Object?> _kept(String name, String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get(path, queryParameters: query);
      final data = response.data;
      if (data != null) await copies?.save(name, data, DateTime.now());
      onAnswer?.call(name, null);
      return data;
    } on DioException catch (error) {
      if (!isNoSignal(error)) rethrow;
      final saved = await copies?.read(name);
      if (saved == null) rethrow;
      onAnswer?.call(name, saved.at);
      return saved.json;
    }
  }

  /// The day as the server sent it, so the repository can keep a copy.
  Future<Map<String, dynamic>> today(int childId) async {
    final response = await _dio.get('/family/children/$childId/today');
    return response.data as Map<String, dynamic>;
  }

  Future<AttendanceMonth> attendance(int childId, String month) async {
    final data = await _kept(
      'attendance:$childId:$month',
      '/family/children/$childId/attendance',
      query: {'month': month},
    );
    return AttendanceMonth.fromJson(data as Map<String, dynamic>);
  }

  Future<SchoolCalendar> calendar(String month) async {
    final data = await _kept('calendar:$month', '/family/calendar', query: {'month': month});
    return SchoolCalendar.fromJson(data as Map<String, dynamic>);
  }

  Future<NoticesPage> notices({int page = 1}) async {
    // The first page is what a parent opens with no signal; later pages
    // need one.
    final json =
        (page == 1
                ? await _kept('notices', '/family/notices', query: {'page': page})
                : (await _dio.get('/family/notices', queryParameters: {'page': page})).data)
            as Map<String, dynamic>;
    final links = json['links'] as Map<String, dynamic>?;

    return NoticesPage(
      notices: [for (final n in json['data'] as List<dynamic>) FamilyNotice.fromJson(n as Map<String, dynamic>)],
      unreadCount: json['unread_count'] as int? ?? 0,
      hasMore: links?['next'] != null,
    );
  }

  Future<void> markRead(int noticeId) => _dio.post('/family/notices/$noticeId/read');

  Future<void> markAllRead() => _dio.post('/family/notices/read-all');

  Future<FamilyNotificationSettings> settings() async {
    final response = await _dio.get('/family/notification-settings');
    return FamilyNotificationSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<FamilyNotificationSettings> saveSetting(String key, bool value) async {
    final response = await _dio.patch('/family/notification-settings', data: {key: value});
    return FamilyNotificationSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<FamilyResults> results(int childId, {int? termId}) async {
    final data = await _kept(
      'results:$childId:${termId ?? 'current'}',
      '/family/children/$childId/results',
      query: {'term_id': ?termId},
    );
    return FamilyResults.fromJson(data as Map<String, dynamic>);
  }

  Future<List<int>> progressReport(int childId, {int? termId}) async {
    final response = await _dio.get<List<int>>(
      '/family/children/$childId/progress-report',
      queryParameters: {'term_id': ?termId},
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }

  Future<FamilyWeek> timetable(int childId) async {
    final data = await _kept('timetable:$childId', '/family/children/$childId/timetable');
    return FamilyWeek.fromJson(data as Map<String, dynamic>);
  }

  Future<List<SubjectSyllabus>> syllabus(int childId) async {
    final json = await _kept('syllabus:$childId', '/family/children/$childId/syllabus') as Map<String, dynamic>;
    return [for (final s in json['subjects'] as List<dynamic>) SubjectSyllabus.fromJson(s as Map<String, dynamic>)];
  }

  /// The class's homework over the last two weeks (M8, 8.1), kept for no
  /// signal like the rest of the learning screens.
  Future<List<HomeworkDay>> homework(int childId) async {
    final json = await _kept('homework:$childId', '/family/children/$childId/homework') as Map<String, dynamic>;
    return [for (final d in json['days'] as List<dynamic>) HomeworkDay.fromJson(d as Map<String, dynamic>)];
  }

  Future<FamilyFees> fees(int childId) async {
    final data = await _kept('fees:$childId', '/family/children/$childId/fees');
    return FamilyFees.fromJson(data as Map<String, dynamic>);
  }

  Future<List<int>> feeStatement(int childId) => _bytes('/family/children/$childId/fees/statement.pdf');

  Future<List<int>> receiptPdf(int childId, int receiptId) =>
      _bytes('/family/children/$childId/receipts/$receiptId/pdf');

  Future<List<FamilyAdmitCard>> admitCards(int childId) async {
    final data = await _kept('admit-cards:$childId', '/family/children/$childId/admit-cards');
    return [
      for (final row in ((data as Map<String, dynamic>)['data'] as List<dynamic>))
        FamilyAdmitCard.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<List<int>> admitCardPdf(int childId, int examinationId) =>
      _bytes('/family/children/$childId/admit-cards/$examinationId/pdf');

  Future<List<int>> _bytes(String path) async {
    final response = await _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
    return response.data ?? const [];
  }

  Future<FamilyBus> bus(int childId) async {
    final data = await _kept('bus:$childId', '/family/children/$childId/bus');
    return FamilyBus.fromJson(data as Map<String, dynamic>);
  }

  Future<FamilyBusLive> busLive(int childId) async {
    final response = await _dio.get('/family/children/$childId/bus/live');
    return FamilyBusLive.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<FamilyAbsenceNote>> absenceNotes(int childId) async {
    final response = await _dio.get('/family/children/$childId/absence-notes');
    final json = response.data as Map<String, dynamic>;
    return [for (final n in json['data'] as List<dynamic>) FamilyAbsenceNote.fromJson(n as Map<String, dynamic>)];
  }

  /// A new note; multipart only when a photo of a doctor's note goes with it.
  Future<FamilyAbsenceNote> sendAbsenceNote(
    int childId, {
    required String startDate,
    required String endDate,
    required String reason,
    List<int>? photo,
    String? photoName,
  }) async {
    final fields = {'start_date': startDate, 'end_date': endDate, 'reason': reason};
    final response = await _dio.post(
      '/family/children/$childId/absence-notes',
      data: photo == null
          ? fields
          : FormData.fromMap({...fields, 'photo': MultipartFile.fromBytes(photo, filename: photoName ?? 'note.jpg')}),
    );
    return FamilyAbsenceNote.fromJson(response.data as Map<String, dynamic>);
  }

  Future<NoticeReply> replyToNotice(int noticeId, {required int studentId, required bool answer, String? note}) async {
    final response = await _dio.post(
      '/family/notices/$noticeId/reply',
      data: {'student_id': studentId, 'answer': answer, 'note': ?note},
    );
    return NoticeReply.fromJson(response.data as Map<String, dynamic>)!;
  }

  Future<List<FamilyCallRequest>> callRequests(int childId) async {
    final response = await _dio.get('/family/children/$childId/call-requests');
    final json = response.data as Map<String, dynamic>;
    return [for (final r in json['data'] as List<dynamic>) FamilyCallRequest.fromJson(r as Map<String, dynamic>)];
  }

  Future<FamilyCallRequest> askForCall(
    int childId, {
    required bool toOffice,
    required String reason,
    String? preferredTime,
  }) async {
    final response = await _dio.post(
      '/family/children/$childId/call-requests',
      data: {'recipient': toOffice ? 'office' : 'class_teacher', 'reason': reason, 'preferred_time': ?preferredTime},
    );
    return FamilyCallRequest.fromJson(response.data as Map<String, dynamic>);
  }
}
