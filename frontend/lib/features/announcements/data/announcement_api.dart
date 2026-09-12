import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/announcement.dart';

final announcementApiProvider = Provider<AnnouncementApi>((ref) => AnnouncementApi(ref.watch(dioClientProvider)));

class AnnouncementApi {
  AnnouncementApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<Announcement>> list({
    int? schoolId,
    AnnouncementAudience? audienceType,
    String? search,
    bool activeOnly = false,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/announcements',
      queryParameters: {
        'school_id': ?schoolId,
        'audience_type': ?audienceType?.apiValue,
        'q': ?search,
        'active_only': ?(activeOnly ? 1 : null),
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Announcement.fromJson);
  }

  Future<Announcement> publish({
    int? schoolId,
    required String title,
    required String body,
    required AnnouncementAudience audienceType,
    int? audienceId,
    required AnnouncementChannels channels,
    String? expiresAt,
  }) async {
    final response = await _dio.post(
      '/announcements',
      data: {
        'school_id': ?schoolId,
        'title': title,
        'body': body,
        'audience_type': audienceType.apiValue,
        'audience_id': ?audienceId,
        'channels': channels.apiValue,
        'expires_at': ?expiresAt,
      },
    );
    return Announcement.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AudiencePreview> preview({
    int? schoolId,
    required AnnouncementAudience audienceType,
    int? audienceId,
    required AnnouncementChannels channels,
  }) async {
    final response = await _dio.get(
      '/announcements/preview',
      queryParameters: {
        'school_id': ?schoolId,
        'audience_type': audienceType.apiValue,
        'audience_id': ?audienceId,
        'channels': channels.apiValue,
      },
    );
    return AudiencePreview.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int announcementId) async {
    await _dio.delete('/announcements/$announcementId');
  }
}
