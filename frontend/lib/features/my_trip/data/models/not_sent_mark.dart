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

  /// The same mark arriving twice - one phone, bad signal.
  duplicate('duplicate'),

  /// Somebody else had already marked this child this way: the driver and
  /// the attendant both tapped Boarded. Not a failure, and nothing to send
  /// again (docs/driver-app.md, D2).
  alreadyMarked('already_marked'),

  rejected('rejected');

  const MarkResultStatus(this.apiValue);

  final String apiValue;

  /// Anything this build does not recognise reads as rejected, which puts
  /// the mark under "Not sent" with the server's own reason. An older app
  /// meeting a newer server must not crash on a word it has not heard of -
  /// it is a bus, mid-run, and the phone is the only record of the marks
  /// still waiting on it.
  static MarkResultStatus fromApiValue(String value) {
    return MarkResultStatus.values.firstWhere((s) => s.apiValue == value, orElse: () => MarkResultStatus.rejected);
  }
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
