/// A mark the server turned down - kept so the attendant can read why, and
/// dismiss it once read. It is never retried: the reason says it cannot be
/// recorded ("The trip had already ended, so this mark was not recorded.").
class NotSentMark {
  const NotSentMark({required this.clientId, required this.tripId, required this.label, required this.reason});

  factory NotSentMark.fromJson(Map<String, dynamic> json) {
    return NotSentMark(
      clientId: json['client_id'] as String,
      tripId: json['trip_id'] as int,
      label: json['label'] as String,
      reason: json['reason'] as String,
    );
  }

  final String clientId;
  final int tripId;
  final String label;
  final String reason;

  Map<String, dynamic> toJson() => {'client_id': clientId, 'trip_id': tripId, 'label': label, 'reason': reason};
}

/// The server's answer for one mark in a sync batch.
enum MarkResultStatus {
  applied('applied'),
  duplicate('duplicate'),
  rejected('rejected');

  const MarkResultStatus(this.apiValue);

  final String apiValue;

  static MarkResultStatus fromApiValue(String value) => MarkResultStatus.values.firstWhere((s) => s.apiValue == value);
}

class MarkResult {
  const MarkResult({required this.clientId, required this.status, this.reason});

  factory MarkResult.fromJson(Map<String, dynamic> json) {
    return MarkResult(
      clientId: json['client_id'] as String,
      status: MarkResultStatus.fromApiValue(json['status'] as String),
      reason: json['reason'] as String?,
    );
  }

  final String clientId;
  final MarkResultStatus status;
  final String? reason;
}
