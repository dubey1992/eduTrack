import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/announcement.dart';
import '../../../core/models/notice_attachment.dart';

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
    required String channels,
    String? expiresAt,
    List<int> attachmentIds = const [],
  }) async {
    final response = await _dio.post(
      '/announcements',
      data: {
        'school_id': ?schoolId,
        'title': title,
        'body': body,
        'audience_type': audienceType.apiValue,
        'audience_id': ?audienceId,
        'channels': channels,
        'expires_at': ?expiresAt,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      },
    );
    return Announcement.fromJson(response.data as Map<String, dynamic>);
  }

  /// One file for a notice not yet published (M9, 8.3): one per request,
  /// which the shared host copes with.
  Future<NoticeAttachment> uploadAttachment({int? schoolId, required String name, required List<int> bytes}) async {
    final response = await _dio.post(
      '/announcement-attachments',
      data: FormData.fromMap({'school_id': ?schoolId, 'file': MultipartFile.fromBytes(bytes, filename: name)}),
    );
    return NoticeAttachment.fromJson(response.data as Map<String, dynamic>);
  }

  /// Takes back a file not yet sent.
  Future<void> removeAttachment(int attachmentId) async {
    await _dio.delete('/announcement-attachments/$attachmentId');
  }

  Future<AudiencePreview> preview({
    int? schoolId,
    required AnnouncementAudience audienceType,
    int? audienceId,
    required String channels,
  }) async {
    final response = await _dio.get(
      '/announcements/preview',
      queryParameters: {
        'school_id': ?schoolId,
        'audience_type': audienceType.apiValue,
        'audience_id': ?audienceId,
        'channels': channels,
      },
    );
    return AudiencePreview.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int announcementId) async {
    await _dio.delete('/announcements/$announcementId');
  }
}
