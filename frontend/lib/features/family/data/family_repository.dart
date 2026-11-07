import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'family_api.dart';
import 'models/family_day.dart';
import 'models/family_records.dart';

final familyRepositoryProvider = Provider<FamilyRepository>((ref) => FamilyRepository(ref.watch(familyApiProvider)));

/// The parent's screens' data, with every failure turned into the app's
/// [Failure].
class FamilyRepository {
  FamilyRepository(this._api);

  final FamilyApi _api;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<FamilyToday> today(int childId) => _call(() => _api.today(childId));

  Future<AttendanceMonth> attendance(int childId, String month) => _call(() => _api.attendance(childId, month));

  Future<SchoolCalendar> calendar(String month) => _call(() => _api.calendar(month));

  Future<NoticesPage> notices({int page = 1}) => _call(() => _api.notices(page: page));

  Future<void> markRead(int noticeId) => _call(() => _api.markRead(noticeId));

  Future<void> markAllRead() => _call(_api.markAllRead);

  Future<FamilyNotificationSettings> settings() => _call(_api.settings);

  Future<FamilyNotificationSettings> saveSetting(String key, bool value) => _call(() => _api.saveSetting(key, value));
}
