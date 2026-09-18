/// One place this account is signed in (Phase 21): a browser or a phone,
/// named by the API from the device that signed in.
class SignedInSession {
  const SignedInSession({
    required this.id,
    required this.device,
    required this.signedInLabel,
    required this.lastUsedLabel,
    required this.isCurrent,
  });

  factory SignedInSession.fromJson(Map<String, dynamic> json) {
    return SignedInSession(
      id: json['id'] as int,
      device: json['device'] as String,
      signedInLabel: json['signed_in_label'] as String?,
      lastUsedLabel: json['last_used_label'] as String?,
      isCurrent: json['current'] as bool? ?? false,
    );
  }

  final int id;

  /// "Chrome on Windows", "the app on Android", or "api-token" for a device
  /// that said nothing about itself.
  final String device;

  /// Already on the school's clock - the API renders these.
  final String? signedInLabel;
  final String? lastUsedLabel;

  /// The session this request came from: signing it out is logging out.
  final bool isCurrent;

  /// How the device reads in a list.
  String get deviceLabel => device == 'api-token' ? 'Unknown device' : device;
}
