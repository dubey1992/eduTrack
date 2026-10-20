/// Where a running trip's bus was last seen, and the next stop it has not
/// reached yet - the answer of `GET /transport/trips/{id}/live`.
class TripLiveLocation {
  const TripLiveLocation({
    required this.tripId,
    required this.status,
    required this.position,
    required this.nextStop,
    this.finishesInSeconds,
  });

  factory TripLiveLocation.fromJson(Map<String, dynamic> json) {
    final position = json['position'] as Map<String, dynamic>?;
    final nextStop = json['next_stop'] as Map<String, dynamic>?;

    return TripLiveLocation(
      tripId: json['trip_id'] as int,
      status: json['status'] as String,
      position: position == null ? null : BusPosition.fromJson(position),
      nextStop: nextStop == null ? null : NextStop.fromJson(nextStop),
      finishesInSeconds: (json['finishes_in_seconds'] as num?)?.round(),
    );
  }

  final int tripId;

  /// The trip's status as an API value (`in_progress`, `completed`, ...).
  final String status;

  /// Null until the attendant's phone has shared a location.
  final BusPosition? position;

  /// Null when every stop has been reached.
  final NextStop? nextStop;

  /// How long until the run is over - the drive still to do on this leg
  /// plus the legs after it. Null on the same terms as [NextStop.etaSeconds].
  final int? finishesInSeconds;

  bool get isInProgress => status == 'in_progress';
}

class BusPosition {
  const BusPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.speedMps,
    required this.heading,
    required this.recordedAt,
    required this.ageSeconds,
    required this.isStale,
  });

  factory BusPosition.fromJson(Map<String, dynamic> json) {
    return BusPosition(
      latitude: json['latitude'] as String,
      longitude: json['longitude'] as String,
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      speedMps: (json['speed_mps'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      recordedAt: json['recorded_at'] as String?,
      ageSeconds: (json['age_seconds'] as num).toInt(),
      isStale: json['is_stale'] as bool,
    );
  }

  /// Decimal degrees, as strings so no precision is lost.
  final String latitude;
  final String longitude;
  final double? accuracyM;
  final double? speedMps;
  final double? heading;
  final String? recordedAt;

  /// How old the position was when the server answered - measured on the
  /// server, so a wrong clock on this device cannot skew it.
  final int ageSeconds;

  /// The phone has gone quiet for longer than the server expects.
  final bool isStale;
}

class NextStop {
  const NextStop({
    required this.id,
    required this.name,
    required this.sequenceNumber,
    required this.latitude,
    required this.longitude,
    required this.straightLineDistanceM,
    this.etaSeconds,
  });

  factory NextStop.fromJson(Map<String, dynamic> json) {
    return NextStop(
      id: json['id'] as int,
      name: json['name'] as String,
      sequenceNumber: json['sequence_number'] as int,
      latitude: json['latitude'] as String?,
      longitude: json['longitude'] as String?,
      straightLineDistanceM: (json['straight_line_distance_m'] as num?)?.toDouble(),
      etaSeconds: (json['eta_seconds'] as num?)?.round(),
    );
  }

  final int id;
  final String name;
  final int sequenceNumber;
  final String? latitude;
  final String? longitude;

  /// As the crow flies from the bus - null when either end has no location.
  final double? straightLineDistanceM;

  /// How long the drive to this stop should take, from the leg durations
  /// stored when the road was worked out. Null wherever those legs do not
  /// describe where the bus is - no position shared, a stop nobody has
  /// placed, or the first stop of the run, which the bus reached by a road
  /// nobody asked Google about.
  final int? etaSeconds;
}
