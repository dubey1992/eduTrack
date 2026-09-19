/// One position from the attendant's phone, for the trip it was taken on.
class LocationPoint {
  const LocationPoint({
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.recordedAt,
    this.speed,
    this.heading,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      tripId: json['trip_id'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
      recordedAt: json['recorded_at'] as String,
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
    );
  }

  final int tripId;
  final double latitude;
  final double longitude;

  /// Metres.
  final double accuracy;

  /// Metres per second, when the device knows it.
  final double? speed;

  /// Degrees from north, when the device knows it.
  final double? heading;

  /// ISO 8601 in UTC, with its zone.
  final String recordedAt;

  /// What the locations endpoint is sent.
  Map<String, dynamic> toApiJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'speed': ?speed,
    'heading': ?heading,
    'recorded_at': recordedAt,
  };

  /// How the phone keeps it while there is no signal.
  Map<String, dynamic> toJson() => {...toApiJson(), 'trip_id': tripId};
}
