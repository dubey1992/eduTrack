import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/communication/data/communication_repository.dart';
import 'package:edutrack_app/features/communication/data/models/message.dart';

import 'communication_fixtures.dart';
import 'fake_pagination.dart';

/// In-memory messages, templates and settings. Filtering is done for real so
/// screen tests can assert on what a filter actually shows.
class FakeCommunicationRepository implements CommunicationRepository {
  FakeCommunicationRepository({
    List<Message>? messages,
    List<MessageTemplate>? templates,
    CommunicationSettings? settings,
    this.failWith,
    this.providerLabel = 'Acme SMS',
    this.providerDelivers = true,
  }) : _messages = messages ?? [],
       _templates = templates ?? [...defaultTemplates],
       _settings = settings ?? defaultSettings;

  /// What the summary reports about the gateway. Defaults to one that
  /// really sends, so only tests about the demo gateway have to think
  /// about it.
  final String providerLabel;
  final bool providerDelivers;

  final List<Message> _messages;
  List<MessageTemplate> _templates;
  CommunicationSettings _settings;

  /// When set, every call throws it.
  Failure? failWith;

  /// The last mutation (retry, template save/reset, settings save).
  Map<String, dynamic>? lastCall;

  /// The last list call, kept apart from mutations so a refresh after a
  /// mutation cannot overwrite what a test wants to assert.
  Map<String, dynamic>? lastListCall;

  List<Message> get messages => List.unmodifiable(_messages);

  CommunicationSettings get settingsValue => _settings;

  void _guard() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<PaginatedResponse<Message>> listMessages({
    int? schoolId,
    MessageCategory? category,
    MessageChannel? channel,
    MessageStatus? status,
    String? dateFrom,
    String? dateTo,
    String? search,
    required int page,
    required int perPage,
  }) async {
    _guard();
    lastListCall = {
      'op': 'listMessages',
      'school_id': schoolId,
      'category': category?.apiValue,
      'channel': channel?.apiValue,
      'status': status?.apiValue,
      'date_from': dateFrom,
      'date_to': dateTo,
      'q': search,
      'page': page,
    };

    final term = search?.toLowerCase();
    final matches = _messages.where((message) {
      if (schoolId != null && message.schoolId != schoolId) return false;
      if (category != null && message.category != category) return false;
      if (channel != null && message.channel != channel) return false;
      if (status != null && message.status != status) return false;
      if (term != null && term.isNotEmpty) {
        final haystack = [message.recipientName, message.studentName ?? '', message.body].join(' ').toLowerCase();
        if (!haystack.contains(term)) return false;
      }
      return true;
    }).toList();

    return paginateFake(matches, page: page, perPage: perPage);
  }

  @override
  Future<MessageSummary> summary({int? schoolId, MessageCategory? category}) async {
    _guard();
    final sent = _messages.where((m) => m.status == MessageStatus.sent).length;
    final failed = _messages.where((m) => m.status == MessageStatus.failed).length;
    final queued = _messages.where((m) => m.status == MessageStatus.queued).length;
    final skipped = _messages.where((m) => m.status == MessageStatus.skipped).length;
    final attempted = sent + failed;

    return MessageSummary(
      sentToday: sent,
      smsSentToday: _messages.where((m) => m.status == MessageStatus.sent && m.channel == MessageChannel.sms).length,
      queuedToday: queued,
      failedToday: failed,
      skippedToday: skipped,
      deliveryRate: attempted == 0 ? null : (sent / attempted * 100),
      total: _messages.length,
      providerLabel: providerLabel,
      providerDelivers: providerDelivers,
    );
  }

  @override
  Future<Message> retry(int messageId) async {
    _guard();
    lastCall = {'op': 'retry', 'message_id': messageId};

    final index = _messages.indexWhere((m) => m.id == messageId);
    final queued = messageAs(_messages[index], status: MessageStatus.queued, failureReason: null);
    _messages[index] = queued;

    return queued;
  }

  @override
  Future<List<MessageTemplate>> listTemplates({int? schoolId}) async {
    _guard();
    lastListCall = {'op': 'listTemplates', 'school_id': schoolId};

    return List.unmodifiable(_templates);
  }

  @override
  Future<MessageTemplate> updateTemplate(String event, {int? schoolId, required String body}) async {
    _guard();
    lastCall = {'op': 'updateTemplate', 'event': event, 'school_id': schoolId, 'body': body};

    final index = _templates.indexWhere((t) => t.event == event);
    final updated = templateAs(_templates[index], body: body, isCustom: true);
    _templates = [..._templates]..[index] = updated;

    return updated;
  }

  @override
  Future<MessageTemplate> resetTemplate(String event, {int? schoolId}) async {
    _guard();
    lastCall = {'op': 'resetTemplate', 'event': event, 'school_id': schoolId};

    final index = _templates.indexWhere((t) => t.event == event);
    final reverted = templateAs(_templates[index], body: _templates[index].defaultBody, isCustom: false);
    _templates = [..._templates]..[index] = reverted;

    return reverted;
  }

  @override
  Future<CommunicationSettings> settings({int? schoolId}) async {
    _guard();
    lastListCall = {'op': 'settings', 'school_id': schoolId};

    return _settings;
  }

  @override
  Future<CommunicationSettings> updateSettings({
    int? schoolId,
    required bool smsEnabled,
    required AttendanceAlertMode attendanceAlerts,
    required bool transportAlertsEnabled,
    required bool leaveAlertsEnabled,
    required String provider,
    String? senderId,
  }) async {
    _guard();
    lastCall = {
      'op': 'updateSettings',
      'school_id': schoolId,
      'sms_enabled': smsEnabled,
      'attendance_alerts': attendanceAlerts.apiValue,
      'transport_alerts_enabled': transportAlertsEnabled,
      'leave_alerts_enabled': leaveAlertsEnabled,
      'provider': provider,
      'sender_id': senderId,
    };

    _settings = CommunicationSettings(
      schoolId: schoolId ?? _settings.schoolId,
      smsEnabled: smsEnabled,
      attendanceAlerts: attendanceAlerts,
      transportAlertsEnabled: transportAlertsEnabled,
      leaveAlertsEnabled: leaveAlertsEnabled,
      provider: provider,
      providerLabel: 'Demo Gateway',
      senderId: senderId,
      availableProviders: _settings.availableProviders,
      isSaved: true,
    );

    return _settings;
  }

  @override
  Future<PaginatedResponse<Message>> inbox({bool unreadOnly = false, required int page, required int perPage}) async {
    _guard();
    lastListCall = {'op': 'inbox', 'unread': unreadOnly, 'page': page};

    final mine = _messages
        .where((m) => m.channel == MessageChannel.inApp)
        .where((m) => !unreadOnly || m.isUnread)
        .toList();

    return paginateFake(mine, page: page, perPage: perPage);
  }

  @override
  Future<int> unreadCount() async {
    _guard();

    return _messages.where((m) => m.channel == MessageChannel.inApp && m.isUnread).length;
  }

  @override
  Future<Message> markRead(int messageId) async {
    _guard();
    lastCall = {'op': 'markRead', 'message_id': messageId};

    final index = _messages.indexWhere((m) => m.id == messageId);
    final read = messageAs(_messages[index], readAt: '2026-09-16T10:00:00.000000Z');
    _messages[index] = read;

    return read;
  }

  @override
  Future<int> markAllRead() async {
    _guard();
    lastCall = {'op': 'markAllRead'};

    var marked = 0;
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].channel == MessageChannel.inApp && _messages[i].isUnread) {
        _messages[i] = messageAs(_messages[i], readAt: '2026-09-16T10:00:00.000000Z');
        marked++;
      }
    }

    return marked;
  }
}
