import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/platform_messaging/data/models/platform_messaging.dart';
import 'package:edutrack_app/features/platform_messaging/data/platform_messaging_repository.dart';

/// Test double for [PlatformMessagingRepository] - keeps one [settings] the
/// way the server would and records what each call was asked for.
class FakePlatformMessagingRepository implements PlatformMessagingRepository {
  FakePlatformMessagingRepository({
    PlatformMessaging? settings,
    this.failGetWith,
    this.failSaveWith,
    this.failTestWith,
    this.failTemplateWith,
  }) : settings = settings ?? platformMessaging();

  PlatformMessaging settings;
  Failure? failGetWith;
  Failure? failSaveWith;
  Failure? failTestWith;
  Failure? failTemplateWith;

  /// When set, [get] waits on it - so a test can look at the loading state.
  Completer<void>? getGate;

  int getCalls = 0;
  int saveCalls = 0;
  String? lastProvider;
  Map<String, String>? lastCredentials;
  MessagingChannel? lastTestChannel;
  String? lastTestTo;
  Map<String, Object?>? lastTemplateSave;
  String? lastTemplateCleared;

  @override
  Future<PlatformMessaging> get() async {
    getCalls++;
    if (getGate != null) await getGate!.future;
    if (failGetWith != null) throw failGetWith!;
    return settings;
  }

  @override
  Future<PlatformMessaging> save({required String provider, required Map<String, String> credentials}) async {
    saveCalls++;
    lastProvider = provider;
    lastCredentials = credentials;
    if (failSaveWith != null) throw failSaveWith!;

    settings = _copy(
      isSaved: true,
      provider: provider,
      // A key sent replaces or (empty) clears; one left out is kept.
      fields: [
        for (final field in settings.fields)
          credentials.containsKey(field.key)
              ? credentialField(
                  field.key,
                  field.label,
                  secret: field.secret,
                  isSet: credentials[field.key]!.isNotEmpty,
                  hint: field.secret || credentials[field.key]!.isEmpty
                      ? null
                      : '…${credentials[field.key]!.substring(credentials[field.key]!.length - 4)}',
                )
              : field,
      ],
      updatedByName: 'Platform Owner',
    );
    return settings;
  }

  @override
  Future<MessagingTestResult> sendTest({required MessagingChannel channel, required String to}) async {
    lastTestChannel = channel;
    lastTestTo = to;
    if (failTestWith != null) throw failTestWith!;

    settings = _copy(
      lastTestedAt: '2026-10-29T09:35:00Z',
      lastTestedAtLabel: '10/29/2026 3:05 PM',
      clearTestError: true,
    );
    return MessagingTestResult(message: 'A test ${channel.label} was sent to $to.', settings: settings);
  }

  @override
  Future<PlatformMessaging> saveTemplate({
    required String event,
    required String templateName,
    required String language,
    required List<String> parameters,
  }) async {
    lastTemplateSave = {'event': event, 'template_name': templateName, 'language': language, 'parameters': parameters};
    if (failTemplateWith != null) throw failTemplateWith!;

    settings = _withTemplate(
      event,
      WhatsappTemplate(templateName: templateName, language: language, parameters: parameters, updatedAt: null),
    );
    return settings;
  }

  @override
  Future<PlatformMessaging> clearTemplate(String event) async {
    lastTemplateCleared = event;
    if (failTemplateWith != null) throw failTemplateWith!;

    settings = _withTemplate(event, null);
    return settings;
  }

  PlatformMessaging _withTemplate(String event, WhatsappTemplate? template) {
    return _copy(
      whatsappTemplates: [
        for (final row in settings.whatsappTemplates)
          row.event == event
              ? WhatsappTemplateEvent(
                  event: row.event,
                  eventLabel: row.eventLabel,
                  tokens: row.tokens,
                  template: template,
                )
              : row,
      ],
    );
  }

  PlatformMessaging _copy({
    bool? isSaved,
    String? provider,
    List<MessagingCredentialField>? fields,
    String? lastTestedAt,
    String? lastTestedAtLabel,
    bool clearTestError = false,
    String? updatedByName,
    List<WhatsappTemplateEvent>? whatsappTemplates,
  }) {
    return PlatformMessaging(
      isSaved: isSaved ?? settings.isSaved,
      provider: provider ?? settings.provider,
      availableProviders: settings.availableProviders,
      fields: fields ?? settings.fields,
      lastTestedAt: lastTestedAt ?? settings.lastTestedAt,
      lastTestedAtLabel: lastTestedAtLabel ?? settings.lastTestedAtLabel,
      lastTestError: clearTestError ? null : settings.lastTestError,
      updatedByName: updatedByName ?? settings.updatedByName,
      whatsappTemplates: whatsappTemplates ?? settings.whatsappTemplates,
    );
  }
}

MessagingCredentialField credentialField(
  String key,
  String label, {
  bool secret = false,
  bool isSet = true,
  String? hint,
}) {
  return MessagingCredentialField(key: key, label: label, secret: secret, isSet: isSet, hint: hint);
}

/// Twilio's four settings, all saved.
List<MessagingCredentialField> savedTwilioFields() {
  return [
    credentialField('account_sid', 'Account SID', hint: '…5678'),
    credentialField('auth_token', 'Auth token', secret: true),
    credentialField('sms_from', 'SMS sender number', hint: '…9999'),
    credentialField('whatsapp_from', 'WhatsApp sender number', hint: '…0199'),
  ];
}

/// Twilio's four settings, none saved.
List<MessagingCredentialField> emptyTwilioFields() {
  return [
    credentialField('account_sid', 'Account SID', isSet: false),
    credentialField('auth_token', 'Auth token', secret: true, isSet: false),
    credentialField('sms_from', 'SMS sender number', isSet: false),
    credentialField('whatsapp_from', 'WhatsApp sender number', isSet: false),
  ];
}

const absentEvent = WhatsappTemplateEvent(
  event: 'attendance.absent',
  eventLabel: 'Marked absent',
  tokens: ['student_name', 'date', 'school_name'],
  template: WhatsappTemplate(
    templateName: 'HX0001',
    language: 'en',
    parameters: ['student_name', 'date'],
    updatedAt: '2026-10-29T09:00:00Z',
  ),
);

const feeReminderEvent = WhatsappTemplateEvent(
  event: 'fees.reminder',
  eventLabel: 'Fee reminder',
  tokens: ['student_name', 'amount', 'due_date'],
  template: null,
);

/// A saved Twilio account; override only what a test is about.
PlatformMessaging platformMessaging({
  bool isSaved = true,
  String provider = 'twilio',
  List<MessagingCredentialField>? fields,
  String? lastTestedAt = '2026-10-28T10:40:00Z',
  String? lastTestedAtLabel = '10/28/2026 4:10 PM',
  String? lastTestError,
  String? updatedByName = 'Platform Owner',
  List<WhatsappTemplateEvent> whatsappTemplates = const [absentEvent, feeReminderEvent],
}) {
  return PlatformMessaging(
    isSaved: isSaved,
    provider: provider,
    availableProviders: const [
      MessagingProviderOption(value: 'log', label: 'Demo Gateway', delivers: false),
      MessagingProviderOption(value: 'twilio', label: 'Twilio', delivers: true),
    ],
    fields: fields ?? savedTwilioFields(),
    lastTestedAt: lastTestedAt,
    lastTestedAtLabel: lastTestedAtLabel,
    lastTestError: lastTestError,
    updatedByName: updatedByName,
    whatsappTemplates: whatsappTemplates,
  );
}

/// What the server shows before anything was ever saved.
PlatformMessaging unsavedPlatformMessaging() {
  return platformMessaging(
    isSaved: false,
    provider: 'log',
    fields: emptyTwilioFields(),
    lastTestedAt: null,
    lastTestedAtLabel: null,
    updatedByName: null,
  );
}
