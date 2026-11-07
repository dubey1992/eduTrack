import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/family_day.dart';
import 'models/family_records.dart';

final familyApiProvider = Provider<FamilyApi>((ref) => FamilyApi(ref.watch(dioClientProvider)));

/// The parent's screens' endpoints (school/views/family.py). Just HTTP.
class FamilyApi {
  FamilyApi(this._dio);

  final Dio _dio;

  Future<FamilyToday> today(int childId) async {
    final response = await _dio.get('/family/children/$childId/today');
    return FamilyToday.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AttendanceMonth> attendance(int childId, String month) async {
    final response = await _dio.get('/family/children/$childId/attendance', queryParameters: {'month': month});
    return AttendanceMonth.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SchoolCalendar> calendar(String month) async {
    final response = await _dio.get('/family/calendar', queryParameters: {'month': month});
    return SchoolCalendar.fromJson(response.data as Map<String, dynamic>);
  }

  Future<NoticesPage> notices({int page = 1}) async {
    final response = await _dio.get('/family/notices', queryParameters: {'page': page});
    final json = response.data as Map<String, dynamic>;
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
}
