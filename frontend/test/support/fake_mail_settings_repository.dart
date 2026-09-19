import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/mail_settings/data/mail_settings_repository.dart';
import 'package:edutrack_app/features/mail_settings/data/models/mail_settings.dart';

/// Test double for [MailSettingsRepository] - keeps one [settings] the way
/// the server would and records what each save and test was asked for.
class FakeMailSettingsRepository implements MailSettingsRepository {
  FakeMailSettingsRepository({MailSettings? settings, this.failGetWith, this.failSaveWith, this.failTestWith})
    : settings = settings ?? mailSettings();

  MailSettings settings;
  Failure? failGetWith;
  Failure? failSaveWith;
  Failure? failTestWith;

  /// When set, [get] waits on it - so a test can look at the loading state.
  Completer<void>? getGate;

  int getCalls = 0;
  int saveCalls = 0;
  Map<String, Object?>? lastSave;
  String? lastTestTo;

  @override
  Future<MailSettings> get() async {
    getCalls++;
    if (getGate != null) await getGate!.future;
    if (failGetWith != null) throw failGetWith!;
    return settings;
  }

  @override
  Future<MailSettings> save({
    required bool isActive,
    required String host,
    required int port,
    required MailEncryption encryption,
    String? username,
    String? password,
    required String fromAddress,
    required String fromName,
  }) async {
    saveCalls++;
    lastSave = {
      'is_active': isActive,
      'host': host,
      'port': port,
      'encryption': encryption.apiValue,
      'username': username,
      'password': password,
      'from_address': fromAddress,
      'from_name': fromName,
    };
    if (failSaveWith != null) throw failSaveWith!;

    settings = mailSettings(
      isActive: isActive,
      host: host,
      port: port,
      encryption: encryption,
      username: username,
      // Left out keeps whatever was stored; empty clears it.
      passwordSet: password == null ? settings.passwordSet : password.isNotEmpty,
      fromAddress: fromAddress,
      fromName: fromName,
      lastTestedAt: settings.lastTestedAt,
      lastTestedAtLabel: settings.lastTestedAtLabel,
      lastTestError: settings.lastTestError,
      updatedByName: 'Platform Owner',
    );
    return settings;
  }

  @override
  Future<MailTestResult> sendTest({required String to}) async {
    lastTestTo = to;
    if (failTestWith != null) throw failTestWith!;

    settings = mailSettings(
      isSaved: settings.isSaved,
      isActive: settings.isActive,
      host: settings.host,
      port: settings.port,
      encryption: settings.encryption,
      username: settings.username,
      passwordSet: settings.passwordSet,
      fromAddress: settings.fromAddress,
      fromName: settings.fromName,
      lastTestedAt: '2026-09-19T05:30:00Z',
      lastTestedAtLabel: '09/19/2026 11:00 AM',
      lastTestError: null,
      updatedByName: settings.updatedByName,
      source: settings.source,
    );
    return MailTestResult(message: 'A test email was sent to $to.', settings: settings);
  }
}

/// Deterministic saved settings; override only what a test is about.
MailSettings mailSettings({
  bool isSaved = true,
  bool isActive = true,
  String host = 'smtp.example.com',
  int port = 587,
  MailEncryption encryption = MailEncryption.tls,
  String? username = 'mailer',
  bool passwordSet = true,
  String fromAddress = 'no-reply@example.com',
  String fromName = 'School365ai',
  String? lastTestedAt = '2026-09-18T10:40:00Z',
  String? lastTestedAtLabel = '09/18/2026 4:10 PM',
  String? lastTestError,
  String? updatedByName = 'Platform Owner',
  String source = 'database',
}) {
  return MailSettings(
    isSaved: isSaved,
    isActive: isActive,
    host: host,
    port: port,
    encryption: encryption,
    username: username,
    passwordSet: passwordSet,
    fromAddress: fromAddress,
    fromName: fromName,
    lastTestedAt: lastTestedAt,
    lastTestedAtLabel: lastTestedAtLabel,
    lastTestError: lastTestError,
    updatedByName: updatedByName,
    source: source,
  );
}

/// What the server shows before anything was ever saved.
MailSettings environmentMailSettings() {
  return mailSettings(
    isSaved: false,
    isActive: false,
    host: 'localhost',
    port: 25,
    encryption: MailEncryption.none,
    username: null,
    passwordSet: false,
    fromAddress: 'hello@example.com',
    fromName: 'Example',
    lastTestedAt: null,
    lastTestedAtLabel: null,
    updatedByName: null,
    source: 'environment',
  );
}
