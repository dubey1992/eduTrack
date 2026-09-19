import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../communication/application/inbox_notifier.dart';
import '../../communication/application/message_page_notifier.dart';
import '../data/announcement_repository.dart';
import '../data/models/announcement.dart';

final announcementPageNotifierProvider = AsyncNotifierProvider<AnnouncementPageNotifier, PagedList<Announcement>>(
  AnnouncementPageNotifier.new,
);

/// The published notices, newest first.
class AnnouncementPageNotifier extends AsyncNotifier<PagedList<Announcement>> {
  int? _schoolId;
  AnnouncementAudience? _audienceType;
  String? _search;
  bool _activeOnly = false;
  int _page = 1;
  int _perPage = 20;

  AnnouncementAudience? get audienceType => _audienceType;

  bool get activeOnly => _activeOnly;

  @override
  Future<PagedList<Announcement>> build() => _fetch();

  Future<PagedList<Announcement>> _fetch() async {
    final response = await ref
        .read(announcementRepositoryProvider)
        .listPage(
          schoolId: _schoolId,
          audienceType: _audienceType,
          search: _search,
          activeOnly: _activeOnly,
          page: _page,
          perPage: _perPage,
        );

    return PagedList(
      items: response.items,
      currentPage: response.currentPage,
      lastPage: response.lastPage,
      total: response.total,
      perPage: response.perPage,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> setFilters({AnnouncementAudience? audienceType, String? search, bool? activeOnly}) async {
    _audienceType = audienceType;
    _search = (search ?? '').trim().isEmpty ? null : search!.trim();
    _activeOnly = activeOnly ?? _activeOnly;
    _page = 1;
    await refresh();
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }

  /// Publishing writes a message per recipient, so the log and the reader's
  /// own inbox both change.
  Future<Announcement> publish({
    int? schoolId,
    required String title,
    required String body,
    required AnnouncementAudience audienceType,
    int? audienceId,
    required String channels,
    String? expiresAt,
  }) async {
    final announcement = await ref
        .read(announcementRepositoryProvider)
        .publish(
          schoolId: schoolId,
          title: title,
          body: body,
          audienceType: audienceType,
          audienceId: audienceId,
          channels: channels,
          expiresAt: expiresAt,
        );

    _page = 1;
    await refresh();
    _invalidateCommunication();

    return announcement;
  }

  Future<void> delete(Announcement announcement) async {
    await ref.read(announcementRepositoryProvider).delete(announcement.id);
    await refresh();
    _invalidateCommunication();
  }

  void _invalidateCommunication() {
    ref.invalidate(messagePageNotifierProvider);
    ref.invalidate(messageSummaryProvider);
    ref.invalidate(inboxNotifierProvider);
    ref.invalidate(unreadCountProvider);
  }
}

/// What a chosen audience would reach, refreshed as the compose form changes.
final audiencePreviewProvider = FutureProvider.autoDispose.family<AudiencePreview, AudienceQuery>((ref, query) {
  // No automatic retry: a refused audience (403) is an answer, not a blip, and
  // retrying leaves the form stuck on "Counting the audience...".
  return ref
      .watch(announcementRepositoryProvider)
      .preview(
        schoolId: query.schoolId,
        audienceType: query.audienceType,
        audienceId: query.audienceId,
        channels: query.channels,
      );
}, retry: (retryCount, error) => null);

/// The compose form's current audience choice, as a provider key.
class AudienceQuery {
  const AudienceQuery({required this.audienceType, required this.channels, this.schoolId, this.audienceId});

  final AnnouncementAudience audienceType;

  /// A comma-separated channel list in API order, e.g. "in_app,sms".
  final String channels;
  final int? schoolId;
  final int? audienceId;

  @override
  bool operator ==(Object other) =>
      other is AudienceQuery &&
      other.audienceType == audienceType &&
      other.channels == channels &&
      other.schoolId == schoolId &&
      other.audienceId == audienceId;

  @override
  int get hashCode => Object.hash(audienceType, channels, schoolId, audienceId);
}
