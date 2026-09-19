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
    this.noticeRecipients = 5,
    this.testConfirmation = 'A test message was sent to +91 9000000000.',
  }) : _messages = messages ?? [],
       _templates = templates ?? [...defaultTemplates],
       _settings = settings ?? defaultSettings;

  /// What the summary reports about the gateway. Defaults to one that
  /// really sends, so only tests about the demo gateway have to think
  /// about it.
  final String providerLabel;
  final bool providerDelivers;

  /// How many people any notice preview or send reports reaching.
  int noticeRecipients;

  /// What a test message comes back with.
  String testConfirmation;

  final List<Message> _messages;
  List<MessageTemplate> _templates;
  CommunicationSettings _settings;

  /// When set, every call throws it.
  Failure? failWith;

  /// The last mutation (retry, template save/reset, settings save, test,
  /// notice send).
  Map<String, dynamic>? lastCall;

  /// The last list, preview or settings read, kept apart from mutations so a
  /// refresh after a mutation cannot overwrite what a test wants to assert.
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

    return _replaceTemplate(event, (current) => templateAs(current, body: body, isCustom: true));
  }

  @override
  Future<MessageTemplate> resetTemplate(String event, {int? schoolId}) async {
    _guard();
    lastCall = {'op': 'resetTemplate', 'event': event, 'school_id': schoolId};

    return _replaceTemplate(event, (current) => templateAs(current, body: current.defaultBody, isCustom: false));
  }

  @override
  Future<MessageTemplate> setWhatsappTemplate(
    String event, {
    int? schoolId,
    required String templateName,
    required String language,
    required List<String> parameters,
  }) async {
    _guard();
    lastCall = {
      'op': 'setWhatsappTemplate',
      'event': event,
      'school_id': schoolId,
      'template_name': templateName,
      'language': language,
      'parameters': parameters,
    };

    final mapping = WhatsAppTemplateMapping(
      templateName: templateName,
      language: language,
      parameters: parameters,
      updatedAt: '2026-09-16T11:00:00.000000Z',
    );

    return _replaceTemplate(event, (current) => templateAs(current, whatsapp: mapping));
  }

  @override
  Future<MessageTemplate> clearWhatsappTemplate(String event, {int? schoolId}) async {
    _guard();
    lastCall = {'op': 'clearWhatsappTemplate', 'event': event, 'school_id': schoolId};

    return _replaceTemplate(event, (current) => templateAs(current, whatsapp: null));
  }

  MessageTemplate _replaceTemplate(String event, MessageTemplate Function(MessageTemplate current) change) {
    final index = _templates.indexWhere((t) => t.event == event);
    final updated = change(_templates[index]);
    _templates = [..._templates]..[index] = updated;

    return updated;
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
    bool? whatsappEnabled,
    String? whatsappProvider,
    bool? emailEnabled,
    Map<String, Map<String, String>>? credentials,
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
      'whatsapp_enabled': whatsappEnabled,
      'whatsapp_provider': whatsappProvider,
      'email_enabled': emailEnabled,
      'credentials': credentials,
    };

    // The same rule as the server: a key left out is kept, a blank clears.
    final status = {for (final entry in _settings.credentials.entries) entry.key: Map.of(entry.value)};
    for (final provider in (credentials ?? const {}).entries) {
      final fields = status.putIfAbsent(provider.key, () => {});
      for (final field in provider.value.entries) {
        final secret = _settings.credentialFields[provider.key]?.any((f) => f.key == field.key && f.secret) ?? false;
        fields[field.key] = field.value.isEmpty
            ? const CredentialStatus(isSet: false)
            : CredentialStatus(isSet: true, hint: secret ? null : '…${field.value.substring(field.value.length - 4)}');
      }
    }

    _settings = CommunicationSettings(
      schoolId: schoolId ?? _settings.schoolId,
      smsEnabled: smsEnabled,
      attendanceAlerts: attendanceAlerts,
      transportAlertsEnabled: transportAlertsEnabled,
      leaveAlertsEnabled: leaveAlertsEnabled,
      provider: provider,
      providerLabel: provider == 'log' ? 'Demo Gateway' : provider,
      providerDelivers: provider != 'log',
      senderId: senderId,
      availableProviders: _settings.availableProviders,
      isSaved: true,
      whatsappEnabled: whatsappEnabled ?? _settings.whatsappEnabled,
      whatsappProvider: whatsappProvider ?? _settings.whatsappProvider,
      whatsappProviderLabel: _settings.whatsappProviderLabel,
      whatsappProviderDelivers: (whatsappProvider ?? _settings.whatsappProvider) != 'log',
      availableWhatsappProviders: _settings.availableWhatsappProviders,
      emailEnabled: emailEnabled ?? _settings.emailEnabled,
      emailDelivers: _settings.emailDelivers,
      credentialFields: _settings.credentialFields,
      credentials: status,
    );

    return _settings;
  }

  @override
  Future<String> testGateway({int? schoolId, required MessageChannel channel, required String to}) async {
    _guard();
    lastCall = {'op': 'testGateway', 'school_id': schoolId, 'channel': channel.apiValue, 'to': to};

    return testConfirmation;
  }

  @override
  Future<NoticeResult> previewNotice({
    int? schoolId,
    required NoticeKind kind,
    required NoticeAudience audienceType,
    int? audienceId,
    NoticeRecipients? recipients,
    required List<MessageChannel> channels,
  }) async {
    _guard();
    lastListCall = {
      'op': 'previewNotice',
      'school_id': schoolId,
      'kind': kind.apiValue,
      'audience_type': audienceType.apiValue,
      'audience_id': audienceId,
      'recipients': recipients?.apiValue,
      'channels': MessageChannel.joined(channels),
    };

    return _noticeResult(audienceType, channels, queued: false, messages: const []);
  }

  @override
  Future<NoticeResult> sendNotice({
    int? schoolId,
    required NoticeKind kind,
    required NoticeAudience audienceType,
    int? audienceId,
    NoticeRecipients? recipients,
    required List<MessageChannel> channels,
    String? subject,
    String? body,
    String? amount,
    String? dueDate,
  }) async {
    _guard();
    lastCall = {
      'op': 'sendNotice',
      'school_id': schoolId,
      'kind': kind.apiValue,
      'audience_type': audienceType.apiValue,
      'audience_id': audienceId,
      'recipients': recipients?.apiValue,
      'channels': [for (final channel in channels) channel.apiValue],
      'subject': subject,
      'body': body,
      'amount': amount,
      'due_date': dueDate,
    };

    // One person is sent at once and lands in the log; a group is queued.
    final individual = audienceType == NoticeAudience.student || audienceType == NoticeAudience.staffMember;
    final sent = <Message>[];

    if (individual) {
      for (final channel in channels) {
        sent.add(
          Message(
            id: _messages.length + sent.length + 100,
            schoolId: schoolId ?? 1,
            event: 'general.message',
            eventLabel: kind.label,
            category: switch (kind) {
              NoticeKind.message => MessageCategory.general,
              NoticeKind.emergency => MessageCategory.emergency,
              NoticeKind.feeReminder => MessageCategory.fee,
            },
            channel: channel,
            recipientName: 'Raj Kumar',
            recipientMobile: '+91 9876543210',
            recipientEmail: channel == MessageChannel.email ? 'raj.kumar@example.com' : null,
            studentId: audienceType == NoticeAudience.student ? audienceId : null,
            studentName: audienceType == NoticeAudience.student ? 'Arjun Kumar' : null,
            subject: subject,
            body: body ?? 'A fee of $amount is due on $dueDate.',
            status: MessageStatus.queued,
            provider: null,
            providerLabel: null,
            failureReason: null,
            sentAt: null,
            readAt: null,
            createdAt: '2026-09-16T11:00:00.000000Z',
            createdAtLabel: '11:00 AM',
            createdOnLabel: '16 Sep 2026',
            sentAtLabel: null,
          ),
        );
      }
      _messages.insertAll(0, sent);
    }

    return _noticeResult(audienceType, channels, queued: !individual, messages: sent);
  }

  NoticeResult _noticeResult(
    NoticeAudience audience,
    List<MessageChannel> channels, {
    required bool queued,
    required List<Message> messages,
  }) {
    // Guardians have no inbox, so an in-app-only notice to them reaches nobody.
    final live = [
      for (final channel in channels)
        if (channel != MessageChannel.inApp || audience.reachesStaff) channel,
    ];
    final reachable = live.isEmpty ? 0 : noticeRecipients;

    return NoticeResult(
      recipients: reachable,
      byChannel: {for (final channel in channels) channel: live.contains(channel) ? reachable : 0},
      channels: live,
      audienceLabel: audience.label,
      queued: queued,
      messages: messages,
    );
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
