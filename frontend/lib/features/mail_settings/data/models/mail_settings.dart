/// How the SMTP connection is secured, as the API names it.
enum MailEncryption {
  none('none', 'None'),
  tls('tls', 'STARTTLS (tls)'),
  ssl('ssl', 'SSL');

  const MailEncryption(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MailEncryption fromApiValue(String value) {
    return MailEncryption.values.firstWhere((e) => e.apiValue == value, orElse: () => MailEncryption.none);
  }
}

/// The SMTP server the platform sends through. When [isSaved] is false the
/// values are the server's environment fallback, shown so the Super Admin
/// can see what is in use before overriding it. The password itself never
/// comes back from the API - only whether one is stored.
class MailSettings {
  const MailSettings({
    required this.isSaved,
    required this.isActive,
    required this.host,
    required this.port,
    required this.encryption,
    required this.username,
    required this.passwordSet,
    required this.fromAddress,
    required this.fromName,
    required this.lastTestedAt,
    required this.lastTestedAtLabel,
    required this.lastTestError,
    required this.updatedByName,
    required this.source,
  });

  factory MailSettings.fromJson(Map<String, dynamic> json) {
    return MailSettings(
      isSaved: json['is_saved'] as bool,
      isActive: json['is_active'] as bool,
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 0,
      encryption: MailEncryption.fromApiValue(json['encryption'] as String? ?? 'none'),
      username: json['username'] as String?,
      passwordSet: json['password_set'] as bool? ?? false,
      fromAddress: json['from_address'] as String? ?? '',
      fromName: json['from_name'] as String? ?? '',
      lastTestedAt: json['last_tested_at'] as String?,
      lastTestedAtLabel: json['last_tested_at_label'] as String?,
      lastTestError: json['last_test_error'] as String?,
      updatedByName: json['updated_by_name'] as String?,
      source: json['source'] as String? ?? 'environment',
    );
  }

  final bool isSaved;
  final bool isActive;
  final String host;
  final int port;
  final MailEncryption encryption;
  final String? username;
  final bool passwordSet;
  final String fromAddress;
  final String fromName;

  /// ISO-8601 instant of the last test email, or null if none was ever sent.
  final String? lastTestedAt;

  /// The same instant, already worded for display by the server.
  final String? lastTestedAtLabel;
  final String? lastTestError;
  final String? updatedByName;

  /// `database` or `environment` - where the values in use come from.
  final String source;

  bool get fromDatabase => source == 'database';
}

/// What the test endpoint hands back: the server's message and the settings
/// with the test's outcome recorded on them.
class MailTestResult {
  const MailTestResult({required this.message, required this.settings});

  factory MailTestResult.fromJson(Map<String, dynamic> json) {
    return MailTestResult(
      message: json['message'] as String,
      settings: MailSettings.fromJson(json['settings'] as Map<String, dynamic>),
    );
  }

  final String message;
  final MailSettings settings;
}
