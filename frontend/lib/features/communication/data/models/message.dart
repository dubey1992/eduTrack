/// The prototype's filter tabs on the Communication Center log.
enum MessageCategory {
  attendance('attendance', 'Attendance'),
  transport('transport', 'Transport'),
  leave('leave', 'Leave'),
  announcement('announcement', 'Announcement');

  const MessageCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MessageCategory fromApiValue(String value) =>
      MessageCategory.values.firstWhere((c) => c.apiValue == value, orElse: () => MessageCategory.announcement);
}

enum MessageChannel {
  sms('sms', 'SMS'),
  inApp('in_app', 'In-app');

  const MessageChannel(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MessageChannel fromApiValue(String value) =>
      MessageChannel.values.firstWhere((c) => c.apiValue == value, orElse: () => MessageChannel.sms);
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
    );
  }

  final String event;
  final String eventLabel;
  final MessageCategory category;
  final List<MessageChannel> channels;
  final String body;
  final String defaultBody;
  final bool isCustom;
  final List<String> tokens;
  final String? updatedByName;
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

/// A school's alert switches.
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
    );
  }

  final int? schoolId;
  final bool smsEnabled;
  final AttendanceAlertMode attendanceAlerts;
  final bool transportAlertsEnabled;
  final bool leaveAlertsEnabled;
  final String provider;
  final String providerLabel;
  final String? senderId;
  final List<SmsProviderOption> availableProviders;

  /// False while the school is still on the shipped defaults.
  final bool isSaved;
}
