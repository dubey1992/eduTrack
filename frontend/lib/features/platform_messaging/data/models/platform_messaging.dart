/// The two ways a message can go out through the platform's account, as the
/// API names them.
enum MessagingChannel {
  sms('sms', 'SMS'),
  whatsapp('whatsapp', 'WhatsApp');

  const MessagingChannel(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// School365ai's own SMS and WhatsApp account, which sends every school's
/// messages (docs/platform-messaging.md). Schools only switch channels on or
/// off; the account itself is the Super Admin's.
///
/// No secret ever comes back from the API - each credential only says
/// whether it is set, and a non-secret one its last four characters.
class PlatformMessaging {
  const PlatformMessaging({
    required this.isSaved,
    required this.provider,
    required this.availableProviders,
    required this.fields,
    required this.lastTestedAt,
    required this.lastTestedAtLabel,
    required this.lastTestError,
    required this.updatedByName,
    required this.whatsappTemplates,
  });

  factory PlatformMessaging.fromJson(Map<String, dynamic> json) {
    return PlatformMessaging(
      isSaved: json['is_saved'] as bool? ?? false,
      provider: json['provider'] as String? ?? 'log',
      availableProviders: [
        for (final option in json['available_providers'] as List? ?? const [])
          MessagingProviderOption.fromJson(option as Map<String, dynamic>),
      ],
      fields: [
        for (final field in json['fields'] as List? ?? const [])
          MessagingCredentialField.fromJson(field as Map<String, dynamic>),
      ],
      lastTestedAt: json['last_tested_at'] as String?,
      lastTestedAtLabel: json['last_tested_at_label'] as String?,
      lastTestError: json['last_test_error'] as String?,
      updatedByName: json['updated_by_name'] as String?,
      whatsappTemplates: [
        for (final event in json['whatsapp_templates'] as List? ?? const [])
          WhatsappTemplateEvent.fromJson(event as Map<String, dynamic>),
      ],
    );
  }

  /// False until the Super Admin saves for the first time; until then the
  /// platform sends through the Demo Gateway.
  final bool isSaved;

  /// `log` (the Demo Gateway) or `twilio`.
  final String provider;
  final List<MessagingProviderOption> availableProviders;

  /// Twilio's settings, whichever provider is chosen.
  final List<MessagingCredentialField> fields;

  /// ISO-8601 instant of the last test message, or null if none was sent.
  final String? lastTestedAt;

  /// The same instant, already worded for display by the server.
  final String? lastTestedAtLabel;
  final String? lastTestError;
  final String? updatedByName;

  /// Every event that can go out by WhatsApp, mapped or not.
  final List<WhatsappTemplateEvent> whatsappTemplates;
}

/// One provider the account may send through.
class MessagingProviderOption {
  const MessagingProviderOption({required this.value, required this.label, required this.delivers});

  factory MessagingProviderOption.fromJson(Map<String, dynamic> json) {
    return MessagingProviderOption(
      value: json['value'] as String,
      label: json['label'] as String? ?? json['value'] as String,
      delivers: json['delivers'] as bool? ?? false,
    );
  }

  final String value;
  final String label;

  /// False for the Demo Gateway, which records messages and sends nothing.
  final bool delivers;
}

/// One of the provider's settings: whether it is stored, and - for one that
/// is not secret - the last four characters of what is stored.
class MessagingCredentialField {
  const MessagingCredentialField({
    required this.key,
    required this.label,
    required this.secret,
    required this.isSet,
    required this.hint,
  });

  factory MessagingCredentialField.fromJson(Map<String, dynamic> json) {
    return MessagingCredentialField(
      key: json['key'] as String,
      label: json['label'] as String? ?? json['key'] as String,
      secret: json['secret'] as bool? ?? false,
      isSet: json['set'] as bool? ?? false,
      hint: json['hint'] as String?,
    );
  }

  final String key;
  final String label;
  final bool secret;
  final bool isSet;

  /// E.g. "…5678"; always null for a secret.
  final String? hint;
}

/// An event that can go out by WhatsApp, and the approved template that
/// carries it - or null, in which case WhatsApp copies of it are skipped.
class WhatsappTemplateEvent {
  const WhatsappTemplateEvent({
    required this.event,
    required this.eventLabel,
    required this.tokens,
    required this.template,
  });

  factory WhatsappTemplateEvent.fromJson(Map<String, dynamic> json) {
    final template = json['template'];

    return WhatsappTemplateEvent(
      event: json['event'] as String,
      eventLabel: json['event_label'] as String? ?? json['event'] as String,
      tokens: List<String>.from(json['tokens'] as List? ?? const []),
      template: template == null ? null : WhatsappTemplate.fromJson(template as Map<String, dynamic>),
    );
  }

  /// E.g. `attendance.absent`.
  final String event;
  final String eventLabel;

  /// The placeholders this event can fill a template's parameters from.
  final List<String> tokens;
  final WhatsappTemplate? template;
}

/// A Twilio Content template and which of the event's tokens fill its
/// numbered parameters: the first token fills {{1}}, the second {{2}}...
class WhatsappTemplate {
  const WhatsappTemplate({
    required this.templateName,
    required this.language,
    required this.parameters,
    required this.updatedAt,
  });

  factory WhatsappTemplate.fromJson(Map<String, dynamic> json) {
    return WhatsappTemplate(
      templateName: json['template_name'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      parameters: List<String>.from(json['parameters'] as List? ?? const []),
      updatedAt: json['updated_at'] as String?,
    );
  }

  /// The Twilio Content SID, e.g. `HX0123...`.
  final String templateName;
  final String language;
  final List<String> parameters;
  final String? updatedAt;
}

/// What the test endpoint hands back: the server's message and the account
/// with the test's outcome recorded on it.
class MessagingTestResult {
  const MessagingTestResult({required this.message, required this.settings});

  factory MessagingTestResult.fromJson(Map<String, dynamic> json) {
    return MessagingTestResult(
      message: json['message'] as String,
      settings: PlatformMessaging.fromJson(json['settings'] as Map<String, dynamic>),
    );
  }

  final String message;
  final PlatformMessaging settings;
}
