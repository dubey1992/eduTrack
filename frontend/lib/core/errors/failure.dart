/// Application-level representation of an API failure, mirroring the
/// backend's standard error response shape: { code, message, details }.
/// See backend CLAUDE.md rule 16 (API Response Standard).
class Failure {
  const Failure({required this.code, required this.message, this.details = const {}});

  factory Failure.network() => const Failure(
    code: 'NETWORK_ERROR',
    message: 'Could not reach the server. Check your connection and try again.',
  );

  factory Failure.unknown([String? message]) =>
      Failure(code: 'UNKNOWN_ERROR', message: message ?? 'Something went wrong. Please try again.');

  final String code;
  final String message;
  final Map<String, dynamic> details;

  /// Field-level validation errors, when [code] is VALIDATION_ERROR.
  /// Shape: { fieldName: [messages] }.
  Map<String, List<String>> get validationErrors {
    final errors = details['errors'];
    if (errors is! Map) return {};

    return errors.map((key, value) => MapEntry(key.toString(), List<String>.from(value as List)));
  }
}
