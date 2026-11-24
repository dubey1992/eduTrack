import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/dio_client.dart';
import 'family_api.dart';
import 'family_saved_copies.dart';
import 'family_today_cache.dart';
import 'models/family_admit_card.dart';
import 'models/family_absence_note.dart';
import 'models/family_bus.dart';
import 'models/family_call_request.dart';
import 'models/family_day.dart';
import 'models/family_fees.dart';
import 'models/family_learning.dart';
import 'models/family_guardian_invite.dart';
import 'models/family_homework.dart';
import 'models/family_records.dart';

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => FamilyRepository(
    ref.watch(familyApiProvider),
    ref.watch(familyTodayCacheProvider),
    copies: ref.watch(familySavedCopiesProvider),
  ),
);

/// The parent's screens' data, with every failure turned into the app's
/// [Failure].
class FamilyRepository {
  FamilyRepository(this._api, this._todayCache, {this.copies});

  final FamilyApi _api;
  final FamilyTodayCache _todayCache;

  /// Where Home's own copy is listed, so signing out forgets it too.
  final FamilySavedCopies? copies;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  /// The child's day from the server, kept on the phone as it comes.
  Future<FamilyToday> today(int childId) async {
    final json = await _call(() => _api.today(childId));
    await _todayCache.save(childId, json, DateTime.now());
    await copies?.remember(FamilyTodayCache.keyFor(childId));
    return FamilyToday.fromJson(json);
  }

  /// The last day this phone saw for the child, and when; null when none.
  Future<({FamilyToday today, DateTime at})?> savedToday(int childId) async {
    final saved = await _todayCache.read(childId);
    if (saved == null) return null;

    try {
      return (today: FamilyToday.fromJson(saved.json), at: saved.at);
    } on Object catch (error) {
      debugPrint('Discarding a saved Home that no longer reads: $error');
      return null;
    }
  }

  Future<AttendanceMonth> attendance(int childId, String month) => _call(() => _api.attendance(childId, month));

  Future<SchoolCalendar> calendar(String month) => _call(() => _api.calendar(month));

  Future<NoticesPage> notices({int page = 1}) => _call(() => _api.notices(page: page));

  Future<void> markRead(int noticeId) => _call(() => _api.markRead(noticeId));

  Future<void> markAllRead() => _call(_api.markAllRead);

  Future<FamilyNotificationSettings> settings() => _call(_api.settings);

  Future<FamilyNotificationSettings> saveSetting(String key, bool value) => _call(() => _api.saveSetting(key, value));

  Future<FamilyResults> results(int childId, {int? termId}) => _call(() => _api.results(childId, termId: termId));

  Future<List<int>> progressReport(int childId, {int? termId}) =>
      _call(() => _api.progressReport(childId, termId: termId));

  Future<FamilyWeek> timetable(int childId) => _call(() => _api.timetable(childId));

  Future<List<SubjectSyllabus>> syllabus(int childId) => _call(() => _api.syllabus(childId));

  Future<List<HomeworkDay>> homework(int childId) => _call(() => _api.homework(childId));

  Future<FamilyFees> fees(int childId) => _call(() => _api.fees(childId));

  Future<List<int>> feeStatement(int childId) => _call(() => _api.feeStatement(childId));

  Future<List<int>> receiptPdf(int childId, int receiptId) => _call(() => _api.receiptPdf(childId, receiptId));

  Future<List<FamilyAdmitCard>> admitCards(int childId) => _call(() => _api.admitCards(childId));

  Future<List<int>> admitCardPdf(int childId, int examinationId) =>
      _call(() => _api.admitCardPdf(childId, examinationId));

  /// The child's bus; null for a child the school does not carry.
  Future<FamilyBus?> bus(int childId) async {
    try {
      return await _call(() => _api.bus(childId));
    } on Failure catch (failure) {
      if (failure.code == 'NOT_FOUND') return null;
      rethrow;
    }
  }

  /// Where the bus is; null when the child's trip is not on the road for
  /// them (BUS_NOT_LIVE) - not a failure, just the bus not being theirs now.
  Future<FamilyBusLive?> busLive(int childId) async {
    try {
      return await _call(() => _api.busLive(childId));
    } on Failure catch (failure) {
      if (failure.code == busNotLive) return null;
      rethrow;
    }
  }

  static const busNotLive = 'BUS_NOT_LIVE';

  Future<List<FamilyAbsenceNote>> absenceNotes(int childId) => _call(() => _api.absenceNotes(childId));

  Future<FamilyAbsenceNote> sendAbsenceNote(
    int childId, {
    required DateTime start,
    required DateTime end,
    required String reason,
    List<int>? photo,
    String? photoName,
  }) => _call(
    () => _api.sendAbsenceNote(
      childId,
      startDate: _day(start),
      endDate: _day(end),
      reason: reason,
      photo: photo,
      photoName: photoName,
    ),
  );

  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<NoticeReply> replyToNotice(int noticeId, {required int studentId, required bool answer, String? note}) =>
      _call(() => _api.replyToNotice(noticeId, studentId: studentId, answer: answer, note: note));

  Future<List<FamilyCallRequest>> callRequests(int childId) => _call(() => _api.callRequests(childId));

  Future<List<FamilyGuardianInvite>> guardianInvites(int childId) => _call(() => _api.guardianInvites(childId));

  Future<FamilyGuardianInvite> askForGuardian(
    int childId, {
    required String name,
    required String mobile,
    required String relationship,
  }) => _call(() => _api.askForGuardian(childId, name: name, mobile: mobile, relationship: relationship));

  Future<FamilyCallRequest> askForCall(
    int childId, {
    required bool toOffice,
    required String reason,
    String? preferredTime,
  }) => _call(() => _api.askForCall(childId, toOffice: toOffice, reason: reason, preferredTime: preferredTime));
}
