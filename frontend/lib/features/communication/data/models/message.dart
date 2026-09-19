/// The prototype's filter tabs on the Communication Center log.
enum MessageCategory {
  attendance('attendance', 'Attendance'),
  transport('transport', 'Transport'),
  leave('leave', 'Leave'),
  announcement('announcement', 'Announcement'),
  // Written by hand in the Communication Center rather than by a module.
  general('general', 'General'),
  emergency('emergency', 'Emergency'),
  fee('fee', 'Fee');

  const MessageCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MessageCategory fromApiValue(String value) =>
      MessageCategory.values.firstWhere((c) => c.apiValue == value, orElse: () => MessageCategory.announcement);
}

/// Declared in the order the API lists channels, which is also the order a
/// comma-separated channel list is written in.
enum MessageChannel {
  sms('sms', 'SMS'),
  inApp('in_app', 'In-app'),
  whatsapp('whatsapp', 'WhatsApp'),
  email('email', 'Email');

  const MessageChannel(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MessageChannel fromApiValue(String value) =>
      MessageChannel.values.firstWhere((c) => c.apiValue == value, orElse: () => MessageChannel.sms);

  /// "in_app,sms,whatsapp" - the chosen channels in API order, for the
  /// endpoints that take a channel list as one string.
  static String joined(Iterable<MessageChannel> chosen) => [
    for (final channel in MessageChannel.values)
      if (chosen.contains(channel)) channel.apiValue,
  ].join(',');

  /// The reverse of [joined]; unknown names are dropped.
  static List<MessageChannel> parseJoined(String value) {
    final names = value.split(',').map((part) => part.trim()).toSet();

    return [
      for (final channel in MessageChannel.values)
        if (names.contains(channel.apiValue)) channel,
    ];
  }
}

enum MessageStatus {
  queued('queued', 'Queued'),
  sent('sent', 'Delivered'),
  failed('failed', 'Failed'),
  skipped('skipped', 'Skipped');

  const MessageStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MessageStatus fromApiValue(String value) =>
      MessageStatus.values.firstWhere((s) => s.apiValue == value, orElse: () => MessageStatus.queued);
}

/// How a school wants attendance alerts handled - the prototype's
/// "Send for" control.
enum AttendanceAlertMode {
  off('off', 'No attendance alerts'),
  absentOnly('absent', 'Absent only'),
  presentAndAbsent('both', 'Present + Absent');

  const AttendanceAlertMode(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AttendanceAlertMode fromApiValue(String value) =>
      AttendanceAlertMode.values.firstWhere((m) => m.apiValue == value, orElse: () => AttendanceAlertMode.absentOnly);
}

/// One message the product sent (or recorded but did not send).
class Message {
  const Message({
    required this.id,
    required this.schoolId,
    required this.event,
    required this.eventLabel,
    required this.category,
    required this.channel,
    required this.recipientName,
    required this.recipientMobile,
    this.recipientEmail,
    required this.studentId,
    required this.studentName,
    required this.subject,
    required this.body,
    required this.status,
    required this.provider,
    required this.providerLabel,
    required this.failureReason,
    required this.sentAt,
    required this.readAt,
    required this.createdAt,
    required this.createdAtLabel,
    required this.createdOnLabel,
    required this.sentAtLabel,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      event: json['event'] as String,
      eventLabel: json['event_label'] as String,
      category: MessageCategory.fromApiValue(json['category'] as String),
      channel: MessageChannel.fromApiValue(json['channel'] as String),
      recipientName: json['recipient_name'] as String,
      recipientMobile: json['recipient_mobile'] as String?,
      recipientEmail: json['recipient_email'] as String?,
      studentId: json['student_id'] as int?,
      studentName: json['student_name'] as String?,
      subject: json['subject'] as String?,
      body: json['body'] as String,
      status: MessageStatus.fromApiValue(json['status'] as String),
      provider: json['provider'] as String?,
      providerLabel: json['provider_label'] as String?,
      failureReason: json['failure_reason'] as String?,
      sentAt: json['sent_at'] as String?,
      readAt: json['read_at'] as String?,
      createdAt: json['created_at'] as String?,
      createdAtLabel: json['created_at_label'] as String?,
      createdOnLabel: json['created_on_label'] as String?,
      sentAtLabel: json['sent_at_label'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final String event;
  final String eventLabel;
  final MessageCategory category;
  final MessageChannel channel;
  final String recipientName;
  final String? recipientMobile;

  /// Where an email copy went, when this is one.
  final String? recipientEmail;
  final int? studentId;
  final String? studentName;

  /// An announcement's title, when this copy came from one.
  final String? subject;
  final String body;
  final MessageStatus status;
  final String? provider;

  /// The gateway's human name, e.g. "Demo Gateway".
  final String? providerLabel;
  final String? failureReason;
  final String? sentAt;
  final String? readAt;
  final String? createdAt;

  /// Rendered server-side in the school's timezone, e.g. "8:42 AM" / "16 Sep 2026".
  final String? createdAtLabel;
  final String? createdOnLabel;
  final String? sentAtLabel;

  bool get isRetryable => status == MessageStatus.failed;

  bool get isUnread => readAt == null;
}

/// The four KPI tiles above the log.
class MessageSummary {
  const MessageSummary({
    required this.sentToday,
    required this.smsSentToday,
    required this.queuedToday,
    required this.failedToday,
    required this.skippedToday,
    required this.deliveryRate,
    required this.total,
    this.providerLabel,
    this.providerDelivers = true,
  });

  factory MessageSummary.fromJson(Map<String, dynamic> json) {
    return MessageSummary(
      sentToday: json['sent_today'] as int? ?? 0,
      smsSentToday: json['sms_sent_today'] as int? ?? 0,
      queuedToday: json['queued_today'] as int? ?? 0,
      failedToday: json['failed_today'] as int? ?? 0,
      skippedToday: json['skipped_today'] as int? ?? 0,
      deliveryRate: (json['delivery_rate'] as num?)?.toDouble(),
      total: json['total'] as int? ?? 0,
      providerLabel: json['provider_label'] as String?,
      // Assume delivery unless the server says otherwise, so an older
      // response can never silently suppress the warning.
      providerDelivers: json['provider_delivers'] as bool? ?? true,
    );
  }

  final int sentToday;

  /// Just the texts, so the "SMS Sent Today" tile does not count in-app copies.
  final int smsSentToday;
  final int queuedToday;
  final int failedToday;
  final int skippedToday;

  /// The gateway actually carrying these messages, e.g. "Demo Gateway".
  final String? providerLabel;

  /// False when that gateway writes messages to a log and sends nothing -
  /// the state a deployment is in before a real SMS provider is configured.
  final bool providerDelivers;

  /// Null when nothing was attempted today, so the screen shows a dash
  /// rather than a misleading 0%.
  final double? deliveryRate;
  final int total;
}

/// One event's wording, with the placeholders it is allowed to use.
class MessageTemplate {
  const MessageTemplate({
    required this.event,
    required this.eventLabel,
    required this.category,
    required this.channels,
    required this.body,
    required this.defaultBody,
    required this.isCustom,
    required this.tokens,
    required this.updatedByName,
    this.isManual = false,
    this.whatsapp,
  });

  factory MessageTemplate.fromJson(Map<String, dynamic> json) {
    return MessageTemplate(
      event: json['event'] as String,
      eventLabel: json['event_label'] as String,
      category: MessageCategory.fromApiValue(json['category'] as String),
      channels: (json['channels'] as List<dynamic>)
          .map((value) => MessageChannel.fromApiValue(value as String))
          .toList(growable: false),
      body: json['body'] as String,
      defaultBody: json['default_body'] as String,
      isCustom: json['is_custom'] as bool? ?? false,
      tokens: (json['tokens'] as List<dynamic>).map((value) => value as String).toList(growable: false),
      updatedByName: json['updated_by_name'] as String?,
      isManual: json['is_manual'] as bool? ?? false,
      whatsapp: json['whatsapp'] == null
          ? null
          : WhatsAppTemplateMapping.fromJson(json['whatsapp'] as Map<String, dynamic>),
    );
  }

  final String event;
  final String eventLabel;
  final MessageCategory category;

  /// Every channel this event can go out on.
  final List<MessageChannel> channels;
  final String body;
  final String defaultBody;
  final bool isCustom;
  final List<String> tokens;
  final String? updatedByName;

  /// True for the events somebody writes by hand (a message, an emergency
  /// alert, a fee reminder) rather than a module firing.
  final bool isManual;

  /// Which of the school's approved WhatsApp templates carries this event,
  /// or null when none is mapped yet.
  final WhatsAppTemplateMapping? whatsapp;
}

/// WhatsApp only delivers templates the provider has approved, so every
/// event maps to one by name, with the event's tokens filling its numbered
/// parameters in order.
class WhatsAppTemplateMapping {
  const WhatsAppTemplateMapping({
    required this.templateName,
    required this.language,
    required this.parameters,
    this.updatedAt,
  });

  factory WhatsAppTemplateMapping.fromJson(Map<String, dynamic> json) {
    return WhatsAppTemplateMapping(
      templateName: json['template_name'] as String,
      language: json['language'] as String? ?? 'en',
      parameters: ((json['parameters'] as List<dynamic>?) ?? const []).map((value) => value as String).toList(),
      updatedAt: json['updated_at'] as String?,
    );
  }

  final String templateName;
  final String language;

  /// Token names, in the order they fill the template's {{1}}, {{2}}, ...
  final List<String> parameters;
  final String? updatedAt;
}

/// A gateway the school may choose.
class SmsProviderOption {
  const SmsProviderOption({required this.value, required this.label});

  factory SmsProviderOption.fromJson(Map<String, dynamic> json) {
    return SmsProviderOption(value: json['value'] as String, label: json['label'] as String);
  }

  final String value;
  final String label;
}

/// One thing a provider asks a school for, e.g. Twilio's account SID.
class CredentialField {
  const CredentialField({required this.key, required this.label, required this.secret});

  factory CredentialField.fromJson(Map<String, dynamic> json) {
    return CredentialField(
      key: json['key'] as String,
      label: json['label'] as String,
      secret: json['secret'] as bool? ?? false,
    );
  }

  final String key;
  final String label;

  /// A secret is never sent back, not even hinted at.
  final bool secret;
}

/// Whether a credential is on file - never its value. A non-secret one
/// carries a hint such as "…5678" so an administrator can tell which account.
class CredentialStatus {
  const CredentialStatus({required this.isSet, this.hint});

  factory CredentialStatus.fromJson(Map<String, dynamic> json) {
    return CredentialStatus(isSet: json['set'] as bool? ?? false, hint: json['hint'] as String?);
  }

  final bool isSet;
  final String? hint;
}

/// A school's alert switches, channels and provider accounts.
class CommunicationSettings {
  const CommunicationSettings({
    required this.schoolId,
    required this.smsEnabled,
    required this.attendanceAlerts,
    required this.transportAlertsEnabled,
    required this.leaveAlertsEnabled,
    required this.provider,
    required this.providerLabel,
    required this.senderId,
    required this.availableProviders,
    required this.isSaved,
    this.providerDelivers = true,
    this.whatsappEnabled = false,
    this.whatsappProvider = 'log',
    this.whatsappProviderLabel = 'Demo Gateway',
    this.whatsappProviderDelivers = false,
    this.availableWhatsappProviders = const [],
    this.emailEnabled = false,
    this.emailDelivers = false,
    this.credentialFields = const {},
    this.credentials = const {},
  });

  factory CommunicationSettings.fromJson(Map<String, dynamic> json) {
    return CommunicationSettings(
      schoolId: json['school_id'] as int?,
      smsEnabled: json['sms_enabled'] as bool? ?? true,
      attendanceAlerts: AttendanceAlertMode.fromApiValue(json['attendance_alerts'] as String),
      transportAlertsEnabled: json['transport_alerts_enabled'] as bool? ?? true,
      leaveAlertsEnabled: json['leave_alerts_enabled'] as bool? ?? true,
      provider: json['provider'] as String,
      providerLabel: json['provider_label'] as String,
      senderId: json['sender_id'] as String?,
      availableProviders: (json['available_providers'] as List<dynamic>)
          .map((value) => SmsProviderOption.fromJson(value as Map<String, dynamic>))
          .toList(growable: false),
      isSaved: json['is_saved'] as bool? ?? false,
      providerDelivers: json['provider_delivers'] as bool? ?? true,
      whatsappEnabled: json['whatsapp_enabled'] as bool? ?? false,
      whatsappProvider: json['whatsapp_provider'] as String? ?? 'log',
      whatsappProviderLabel: json['whatsapp_provider_label'] as String? ?? 'Demo Gateway',
      whatsappProviderDelivers: json['whatsapp_provider_delivers'] as bool? ?? false,
      availableWhatsappProviders: ((json['available_whatsapp_providers'] as List<dynamic>?) ?? const [])
          .map((value) => SmsProviderOption.fromJson(value as Map<String, dynamic>))
          .toList(growable: false),
      emailEnabled: json['email_enabled'] as bool? ?? false,
      emailDelivers: json['email_delivers'] as bool? ?? false,
      credentialFields: _credentialFieldsFromJson(json['credential_fields']),
      credentials: _credentialsFromJson(json['credentials']),
    );
  }

  static Map<String, List<CredentialField>> _credentialFieldsFromJson(Object? raw) {
    if (raw is! Map) return const {};

    return {
      for (final entry in raw.entries)
        entry.key.toString(): ((entry.value as List<dynamic>?) ?? const [])
            .map((value) => CredentialField.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
    };
  }

  static Map<String, Map<String, CredentialStatus>> _credentialsFromJson(Object? raw) {
    if (raw is! Map) return const {};

    return {
      for (final entry in raw.entries)
        entry.key.toString(): {
          for (final field in ((entry.value as Map?) ?? const {}).entries)
            field.key.toString(): CredentialStatus.fromJson(field.value as Map<String, dynamic>),
        },
    };
  }

  final int? schoolId;
  final bool smsEnabled;
  final AttendanceAlertMode attendanceAlerts;
  final bool transportAlertsEnabled;
  final bool leaveAlertsEnabled;

  /// The SMS gateway.
  final String provider;
  final String providerLabel;

  /// False when the SMS gateway writes to a log and sends nothing.
  final bool providerDelivers;
  final String? senderId;
  final List<SmsProviderOption> availableProviders;

  /// False while the school is still on the shipped defaults.
  final bool isSaved;

  final bool whatsappEnabled;
  final String whatsappProvider;
  final String whatsappProviderLabel;
  final bool whatsappProviderDelivers;
  final List<SmsProviderOption> availableWhatsappProviders;

  final bool emailEnabled;

  /// False when the platform has no SMTP server set up yet, so email copies
  /// would be recorded but go nowhere.
  final bool emailDelivers;

  /// What each provider asks for, keyed by provider name ("twilio", "meta").
  /// A provider that needs nothing (the demo gateway) is not listed.
  final Map<String, List<CredentialField>> credentialFields;

  /// Which of those are on file, per provider - never the values.
  final Map<String, Map<String, CredentialStatus>> credentials;

  /// The channels this school has switched on. The inbox is always there.
  List<MessageChannel> get enabledChannels => [
    if (smsEnabled) MessageChannel.sms,
    MessageChannel.inApp,
    if (whatsappEnabled) MessageChannel.whatsapp,
    if (emailEnabled) MessageChannel.email,
  ];

  CredentialStatus statusOf(String provider, String key) =>
      credentials[provider]?[key] ?? const CredentialStatus(isSet: false);
}

/// What somebody in the Communication Center is writing by hand.
enum NoticeKind {
  message('message', 'Message'),
  emergency('emergency', 'Emergency alert'),
  feeReminder('fee_reminder', 'Fee reminder');

  const NoticeKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static NoticeKind fromApiValue(String value) =>
      NoticeKind.values.firstWhere((k) => k.apiValue == value, orElse: () => NoticeKind.message);
}

/// Who a notice is for. The first two name one person and are sent at once;
/// the rest are groups and are fanned out by the queue.
enum NoticeAudience {
  student('student', 'One student'),
  staffMember('staff_member', 'One staff member'),
  classSection('class_section', 'A class section'),
  department('department', 'A department'),
  parents('parents', 'All parents'),
  students('students', 'All students'),
  teachers('teachers', 'All teachers'),
  staff('staff', 'All staff'),
  everyone('everyone', 'Everyone');

  const NoticeAudience(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Audiences that name one person, class or department.
  bool get needsTarget =>
      this == NoticeAudience.student ||
      this == NoticeAudience.staffMember ||
      this == NoticeAudience.classSection ||
      this == NoticeAudience.department;

  /// Audiences made of students where the form gets to choose whether the
  /// guardians, the students themselves, or both receive it.
  bool get choosesRecipients =>
      this == NoticeAudience.student || this == NoticeAudience.classSection || this == NoticeAudience.everyone;

  /// Audiences with an inbox to read.
  bool get reachesStaff =>
      this == NoticeAudience.staffMember ||
      this == NoticeAudience.department ||
      this == NoticeAudience.teachers ||
      this == NoticeAudience.staff ||
      this == NoticeAudience.everyone;

  static NoticeAudience fromApiValue(String value) =>
      NoticeAudience.values.firstWhere((a) => a.apiValue == value, orElse: () => NoticeAudience.everyone);
}

/// For an audience made of students: who actually receives it.
enum NoticeRecipients {
  guardians('guardians', 'Parents / guardians'),
  students('students', 'Students themselves'),
  both('both', 'Both');

  const NoticeRecipients(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static NoticeRecipients fromApiValue(String value) =>
      NoticeRecipients.values.firstWhere((r) => r.apiValue == value, orElse: () => NoticeRecipients.guardians);
}

/// What a notice reached, or would reach - the preview and the send return
/// the same shape, the preview with [queued] false and no [messages].
class NoticeResult {
  const NoticeResult({
    required this.recipients,
    required this.byChannel,
    required this.channels,
    required this.audienceLabel,
    required this.queued,
    required this.messages,
  });

  factory NoticeResult.fromJson(Map<String, dynamic> json) {
    final counts = (json['by_channel'] as Map?) ?? const {};

    return NoticeResult(
      recipients: json['recipients'] as int? ?? 0,
      byChannel: {
        for (final channel in MessageChannel.values)
          if (counts[channel.apiValue] != null) channel: counts[channel.apiValue] as int,
      },
      channels: ((json['channels'] as List<dynamic>?) ?? const [])
          .map((value) => MessageChannel.fromApiValue(value as String))
          .toList(growable: false),
      audienceLabel: json['audience_label'] as String? ?? '',
      queued: json['queued'] as bool? ?? false,
      messages: ((json['messages'] as List<dynamic>?) ?? const [])
          .map((value) => Message.fromJson(value as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final int recipients;
  final Map<MessageChannel, int> byChannel;

  /// The channels that will actually carry it.
  final List<MessageChannel> channels;
  final String audienceLabel;

  /// True when a group was handed to the queue rather than sent at once.
  final bool queued;
  final List<Message> messages;

  int countFor(MessageChannel channel) => byChannel[channel] ?? 0;
}
