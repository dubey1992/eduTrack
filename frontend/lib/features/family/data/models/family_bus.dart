/// The school bus as the Family app shows it (docs/parent-student-app.md,
/// F4): the child's route, stop and vehicle, who to call, today's trips as
/// they went for the child, and - only during their own trip - where the
/// bus is.
library;

/// A latitude/longitude the server sent as two strings.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  static GeoPoint? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return GeoPoint(double.parse(json['latitude'] as String), double.parse(json['longitude'] as String));
  }

  final double latitude;
  final double longitude;
}

class FamilyBus {
  const FamilyBus({
    required this.routeName,
    required this.vehicleName,
    required this.vehicleNumber,
    required this.stop,
    required this.officePhone,
    required this.attendant,
    required this.trips,
  });

  factory FamilyBus.fromJson(Map<String, dynamic> json) {
    final vehicle = json['vehicle'] as Map<String, dynamic>?;
    final stop = json['stop'] as Map<String, dynamic>?;
    final contacts = json['contacts'] as Map<String, dynamic>;
    final attendant = contacts['attendant'] as Map<String, dynamic>?;

    return FamilyBus(
      routeName: (json['route'] as Map<String, dynamic>)['name'] as String,
      vehicleName: vehicle?['name'] as String?,
      vehicleNumber: vehicle?['registration_number'] as String?,
      stop: stop == null ? null : BusStopInfo.fromJson(stop),
      officePhone: contacts['office_phone'] as String?,
      attendant: attendant == null ? null : (name: attendant['name'] as String, mobile: attendant['mobile'] as String),
      trips: [for (final t in json['trips'] as List<dynamic>) FamilyBusTrip.fromJson(t as Map<String, dynamic>)],
    );
  }

  final String routeName;
  final String? vehicleName;
  final String? vehicleNumber;
  final BusStopInfo? stop;
  final String? officePhone;

  /// The bus attendant, only when the school lets parents have the number.
  final ({String name, String mobile})? attendant;
  final List<FamilyBusTrip> trips;

  /// Today's trip the parent can follow on the map now, if any.
  FamilyBusTrip? get liveTrip => trips.where((trip) => trip.isLive).firstOrNull;
}

class BusStopInfo {
  const BusStopInfo({required this.name, this.pickupTime, this.dropTime, this.location});

  factory BusStopInfo.fromJson(Map<String, dynamic> json) => BusStopInfo(
    name: json['name'] as String,
    pickupTime: json['pickup_time'] as String?,
    dropTime: json['drop_time'] as String?,
    location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>?),
  );

  final String name;

  /// "07:35" on the school's clock.
  final String? pickupTime;
  final String? dropTime;
  final GeoPoint? location;
}

class FamilyBusTrip {
  const FamilyBusTrip({
    required this.id,
    required this.direction,
    required this.status,
    this.startedAt,
    this.endedAt,
    this.reachedStopAt,
    this.riderStatus,
    this.boardedAt,
    this.droppedAt,
    required this.isLive,
  });

  factory FamilyBusTrip.fromJson(Map<String, dynamic> json) => FamilyBusTrip(
    id: json['id'] as int,
    direction: json['direction'] as String,
    status: json['status'] as String,
    startedAt: json['started_at'] as String?,
    endedAt: json['ended_at'] as String?,
    reachedStopAt: json['reached_stop_at'] as String?,
    riderStatus: json['rider_status'] as String?,
    boardedAt: json['boarded_at'] as String?,
    droppedAt: json['dropped_at'] as String?,
    isLive: json['is_live'] as bool? ?? false,
  );

  final int id;

  /// pickup or drop.
  final String direction;

  /// in_progress, completed or cancelled.
  final String status;

  /// Times on the school's clock, "07:41".
  final String? startedAt;
  final String? endedAt;
  final String? reachedStopAt;

  /// pending, boarded, dropped or absent; null when the child is not on the trip's list.
  final String? riderStatus;
  final String? boardedAt;
  final String? droppedAt;

  /// The parent may follow this trip on the map now.
  final bool isLive;

  bool get isPickup => direction == 'pickup';
  bool get isCancelled => status == 'cancelled';
}

/// Where the bus is now, during the child's own trip.
class FamilyBusLive {
  const FamilyBusLive({
    required this.direction,
    required this.position,
    required this.routePath,
    required this.yourStop,
    required this.nextStop,
  });

  factory FamilyBusLive.fromJson(Map<String, dynamic> json) {
    final position = json['position'] as Map<String, dynamic>?;
    final stop = json['your_stop'] as Map<String, dynamic>?;

    return FamilyBusLive(
      direction: json['direction'] as String,
      position: position == null
          ? null
          : BusPosition(
              point: GeoPoint(
                double.parse(position['latitude'] as String),
                double.parse(position['longitude'] as String),
              ),
              heading: (position['heading'] as num?)?.toDouble(),
              ageSeconds: position['age_seconds'] as int,
              isStale: position['is_stale'] as bool,
            ),
      routePath: json['route_path'] as String?,
      yourStop: stop == null
          ? null
          : YourStop(
              name: stop['name'] as String,
              location: GeoPoint.fromJson(stop['location'] as Map<String, dynamic>?),
              reached: stop['reached'] as bool,
              stopsBefore: stop['stops_before'] as int?,
              distanceM: stop['distance_m'] as int?,
              etaSeconds: stop['eta_seconds'] as int?,
            ),
      nextStop: json['next_stop'] as String?,
    );
  }

  final String direction;

  /// Null until the crew's phone has shared a position.
  final BusPosition? position;

  /// The route's road, Google's encoded polyline; null when never worked out.
  final String? routePath;
  final YourStop? yourStop;
  final String? nextStop;
}

class BusPosition {
  const BusPosition({required this.point, this.heading, required this.ageSeconds, required this.isStale});

  final GeoPoint point;
  final double? heading;
  final int ageSeconds;

  /// No new position for a couple of minutes: the phone may be out of signal.
  final bool isStale;
}

class YourStop {
  const YourStop({
    required this.name,
    this.location,
    required this.reached,
    this.stopsBefore,
    this.distanceM,
    this.etaSeconds,
  });

  final String name;
  final GeoPoint? location;

  /// The bus has been to the stop already on this trip.
  final bool reached;

  /// Stops the bus still has to make before this one.
  final int? stopsBefore;
  final int? distanceM;

  /// How long until the bus reaches it; only known once it is the next stop.
  final int? etaSeconds;
}
