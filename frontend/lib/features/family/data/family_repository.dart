import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/dio_client.dart';
import 'family_api.dart';
import 'family_today_cache.dart';
import 'models/family_bus.dart';
import 'models/family_day.dart';
import 'models/family_fees.dart';
import 'models/family_learning.dart';
import 'models/family_records.dart';

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => FamilyRepository(ref.watch(familyApiProvider), ref.watch(familyTodayCacheProvider)),
);

/// The parent's screens' data, with every failure turned into the app's
/// [Failure].
class FamilyRepository {
  FamilyRepository(this._api, this._todayCache);

  final FamilyApi _api;
  final FamilyTodayCache _todayCache;

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

  Future<FamilyFees> fees(int childId) => _call(() => _api.fees(childId));

  Future<List<int>> feeStatement(int childId) => _call(() => _api.feeStatement(childId));

  Future<List<int>> receiptPdf(int childId, int receiptId) => _call(() => _api.receiptPdf(childId, receiptId));

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
}
