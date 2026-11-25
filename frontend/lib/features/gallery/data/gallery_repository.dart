import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/picked_file.dart';
import 'gallery_models.dart';

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) => GalleryRepository(ref.watch(dioClientProvider)));

/// Events and photos as the school posts them (M12, 8.6).
class GalleryRepository {
  GalleryRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<GalleryEvent>> list({int page = 1}) => _call(() async {
    final response = await _dio.get('/gallery-events', queryParameters: {'page': page});
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, GalleryEvent.fromJson);
  });

  Future<GalleryEvent> get(int id) => _call(() async {
    final response = await _dio.get('/gallery-events/$id');
    return GalleryEvent.fromJson(response.data as Map<String, dynamic>);
  });

  Map<String, dynamic> _body(GalleryEventDraft draft) => {
    'school_id': ?draft.schoolId,
    'class_section_id': draft.classSectionId,
    'title': draft.title,
    'event_date': apiDate(draft.date),
    'description': draft.description,
  };

  Future<GalleryEvent> create(GalleryEventDraft draft) => _call(() async {
    final response = await _dio.post('/gallery-events', data: _body(draft));
    return GalleryEvent.fromJson(response.data as Map<String, dynamic>);
  });

  Future<GalleryEvent> update(int id, GalleryEventDraft draft) => _call(() async {
    final response = await _dio.patch('/gallery-events/$id', data: _body(draft));
    return GalleryEvent.fromJson(response.data as Map<String, dynamic>);
  });

  Future<void> delete(int id) => _call(() => _dio.delete('/gallery-events/$id'));

  /// One photo per request, so no single upload is large on the host.
  Future<GalleryEvent> addPhoto(int eventId, PickedFile file) => _call(() async {
    final form = FormData.fromMap({'photo': MultipartFile.fromBytes(file.bytes, filename: file.name)});
    final response = await _dio.post('/gallery-events/$eventId/photos', data: form);
    return GalleryEvent.fromJson(response.data as Map<String, dynamic>);
  });

  Future<void> removePhoto(int photoId) => _call(() => _dio.delete('/gallery-photos/$photoId'));
}
