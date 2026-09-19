import 'dart:math';

/// The kinds of mark an attendant makes on the bus - the `type` values the
/// sync endpoint takes (POST /transport/trips/{id}/sync).
enum TripMarkType {
  stopReached('stop_reached'),
  boarded('boarded'),
  dropped('dropped'),
  absent('absent'),
  guardianCalled('guardian_called'),
  end('end');

  const TripMarkType(this.apiValue);

  final String apiValue;

  static TripMarkType fromApiValue(String value) => TripMarkType.values.firstWhere((t) => t.apiValue == value);
}

/// One mark made on the bus and saved on the phone first (docs/maps.md,
/// "Offline"): what happened, to which stop or child, when - and a unique
/// id, so sending it twice is harmless.
class TripMark {
  const TripMark({
    required this.clientId,
    required this.tripId,
    required this.type,
    required this.occurredAt,
    required this.label,
    this.stopId,
    this.studentId,
  });

  /// A new mark happening now.
  factory TripMark.now({
    required int tripId,
    required TripMarkType type,
    required String label,
    int? stopId,
    int? studentId,
  }) {
    return TripMark(
      clientId: newClientId(),
      tripId: tripId,
      type: type,
      occurredAt: DateTime.now().toUtc().toIso8601String(),
      label: label,
      stopId: stopId,
      studentId: studentId,
    );
  }

  factory TripMark.fromJson(Map<String, dynamic> json) {
    return TripMark(
      clientId: json['client_id'] as String,
      tripId: json['trip_id'] as int,
      type: TripMarkType.fromApiValue(json['type'] as String),
      occurredAt: json['occurred_at'] as String,
      label: json['label'] as String? ?? '',
      stopId: json['stop_id'] as int?,
      studentId: json['student_id'] as int?,
    );
  }

  final String clientId;
  final int tripId;
  final TripMarkType type;

  /// ISO 8601 in UTC, with its zone - the server refuses a time without one.
  final String occurredAt;

  /// What the attendant did, in words ("Aarav boarded") - kept on the phone
  /// only, to name the mark if the server turns it down.
  final String label;
  final int? stopId;
  final int? studentId;

  /// How the phone keeps it.
  Map<String, dynamic> toJson() => {...toSyncJson(), 'trip_id': tripId, 'label': label};

  /// What the sync endpoint is sent.
  Map<String, dynamic> toSyncJson() => {
    'client_id': clientId,
    'type': type.apiValue,
    'occurred_at': occurredAt,
    'stop_id': ?stopId,
    'student_id': ?studentId,
  };

  static final _random = Random.secure();

  /// 32 random hex characters - inside the server's 8-64 [A-Za-z0-9_-].
  static String newClientId() {
    return List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
