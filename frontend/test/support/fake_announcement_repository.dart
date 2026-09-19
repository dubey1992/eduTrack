import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/announcements/data/announcement_repository.dart';
import 'package:edutrack_app/features/announcements/data/models/announcement.dart';
import 'package:edutrack_app/features/communication/data/models/message.dart';

import 'fake_pagination.dart';

/// In-memory announcements. Publishing appends a row with the counts the
/// preview reported, so screens can assert on what they would really show.
class FakeAnnouncementRepository implements AnnouncementRepository {
  FakeAnnouncementRepository({List<Announcement>? announcements, this.previewRecipients = 6, this.failWith})
    : _announcements = announcements ?? [];

  final List<Announcement> _announcements;

  /// What the audience preview reports for any query.
  int previewRecipients;

  /// When set, every call throws it.
  Failure? failWith;

  /// The last mutation (publish or delete).
  Map<String, dynamic>? lastCall;

  /// The last list or preview call.
  Map<String, dynamic>? lastListCall;

  List<Announcement> get announcements => List.unmodifiable(_announcements);

  void _guard() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<PaginatedResponse<Announcement>> listPage({
    int? schoolId,
    AnnouncementAudience? audienceType,
    String? search,
    bool activeOnly = false,
    required int page,
    required int perPage,
  }) async {
    _guard();
    lastListCall = {
      'op': 'list',
      'school_id': schoolId,
      'audience_type': audienceType?.apiValue,
      'q': search,
      'active_only': activeOnly,
      'page': page,
    };

    final term = search?.toLowerCase();
    final matches = _announcements.where((announcement) {
      if (schoolId != null && announcement.schoolId != schoolId) return false;
      if (audienceType != null && announcement.audienceType != audienceType) return false;
      if (activeOnly && announcement.hasExpired) return false;
      if (term != null && term.isNotEmpty) {
        final haystack = '${announcement.title} ${announcement.body}'.toLowerCase();
        if (!haystack.contains(term)) return false;
      }
      return true;
    }).toList();

    return paginateFake(matches, page: page, perPage: perPage);
  }

  @override
  Future<Announcement> publish({
    int? schoolId,
    required String title,
    required String body,
    required AnnouncementAudience audienceType,
    int? audienceId,
    required String channels,
    String? expiresAt,
  }) async {
    _guard();
    lastCall = {
      'op': 'publish',
      'school_id': schoolId,
      'title': title,
      'body': body,
      'audience_type': audienceType.apiValue,
      'audience_id': audienceId,
      'channels': channels,
      'expires_at': expiresAt,
    };

    final chosen = announcementChannelsOf(channels);
    final published = Announcement(
      id: _announcements.length + 100,
      schoolId: schoolId ?? 1,
      schoolName: 'Sunrise Public School',
      title: title,
      body: body,
      audienceType: audienceType,
      audienceId: audienceId,
      audienceLabel: audienceType.needsTarget ? 'Grade 8 A' : audienceType.label,
      channels: channels,
      channelsLabel: chosen.map((c) => c.label).join(' + '),
      expiresAt: expiresAt,
      hasExpired: false,
      publishedByName: 'Anita Sharma',
      publishedAt: '2026-09-16T09:00:00.000000Z',
      recipientsCount: previewRecipients,
      smsCount: chosen.contains(MessageChannel.sms) ? previewRecipients : 0,
      inAppCount: chosen.contains(MessageChannel.inApp) ? previewRecipients : 0,
    );

    _announcements.insert(0, published);

    return published;
  }

  @override
  Future<AudiencePreview> preview({
    int? schoolId,
    required AnnouncementAudience audienceType,
    int? audienceId,
    required String channels,
  }) async {
    _guard();
    lastListCall = {
      'op': 'preview',
      'school_id': schoolId,
      'audience_type': audienceType.apiValue,
      'audience_id': audienceId,
      'channels': channels,
    };

    final chosen = announcementChannelsOf(channels);
    // Guardians have no login, so an in-app-only notice to them reaches nobody.
    final inAppOnly = chosen.every((c) => c == MessageChannel.inApp);
    final reachable = inAppOnly && !audienceType.reachesStaff ? 0 : previewRecipients;

    return AudiencePreview(
      recipients: reachable,
      sms: chosen.contains(MessageChannel.sms) ? reachable : 0,
      inApp: chosen.contains(MessageChannel.inApp) ? reachable : 0,
      whatsapp: chosen.contains(MessageChannel.whatsapp) ? reachable : 0,
      email: chosen.contains(MessageChannel.email) ? reachable : 0,
      audienceLabel: audienceType.needsTarget ? 'Grade 8 A' : audienceType.label,
    );
  }

  @override
  Future<void> delete(int announcementId) async {
    _guard();
    lastCall = {'op': 'delete', 'announcement_id': announcementId};
    _announcements.removeWhere((announcement) => announcement.id == announcementId);
  }
}
