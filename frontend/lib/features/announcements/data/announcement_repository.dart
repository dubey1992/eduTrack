import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'announcement_api.dart';
import 'models/announcement.dart';

final announcementRepositoryProvider = Provider<AnnouncementRepository>(
  (ref) => AnnouncementRepository(ref.watch(announcementApiProvider)),
);

class AnnouncementRepository {
  AnnouncementRepository(this._api);

  final AnnouncementApi _api;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<Announcement>> listPage({
    int? schoolId,
    AnnouncementAudience? audienceType,
    String? search,
    bool activeOnly = false,
    required int page,
    required int perPage,
  }) {
    return _guard(
      () => _api.list(
        schoolId: schoolId,
        audienceType: audienceType,
        search: search,
        activeOnly: activeOnly,
        page: page,
        perPage: perPage,
      ),
    );
  }

  Future<Announcement> publish({
    int? schoolId,
    required String title,
    required String body,
    required AnnouncementAudience audienceType,
    int? audienceId,
    required AnnouncementChannels channels,
    String? expiresAt,
  }) {
    return _guard(
      () => _api.publish(
        schoolId: schoolId,
        title: title,
        body: body,
        audienceType: audienceType,
        audienceId: audienceId,
        channels: channels,
        expiresAt: expiresAt,
      ),
    );
  }

  Future<AudiencePreview> preview({
    int? schoolId,
    required AnnouncementAudience audienceType,
    int? audienceId,
    required AnnouncementChannels channels,
  }) {
    return _guard(
      () => _api.preview(schoolId: schoolId, audienceType: audienceType, audienceId: audienceId, channels: channels),
    );
  }

  Future<void> delete(int announcementId) => _guard(() => _api.delete(announcementId));
}
