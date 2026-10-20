import 'transport_status.dart';

class TransportStop {
  const TransportStop({
    required this.id,
    required this.routeId,
    required this.name,
    required this.sequenceNumber,
    required this.pickupTime,
    required this.dropTime,
    required this.studentsCount,
    this.latitude,
    this.longitude,
  });

  factory TransportStop.fromJson(Map<String, dynamic> json) {
    return TransportStop(
      id: json['id'] as int,
      routeId: json['route_id'] as int,
      name: json['name'] as String,
      sequenceNumber: json['sequence_number'] as int,
      pickupTime: json['pickup_time'] as String?,
      dropTime: json['drop_time'] as String?,
      studentsCount: json['students_count'] as int? ?? 0,
      latitude: json['latitude'] as String?,
      longitude: json['longitude'] as String?,
    );
  }

  final int id;
  final int routeId;
  final String name;
  final int sequenceNumber;

  /// `HH:mm`, or null when not scheduled.
  final String? pickupTime;
  final String? dropTime;
  final int studentsCount;

  /// Decimal degrees as the API sends them (strings, so no precision is lost
  /// on the way through); both null until the stop is placed.
  final String? latitude;
  final String? longitude;

  bool get hasLocation => latitude != null && longitude != null;
}

/// A route with its current vehicle/driver and, when fetched individually,
/// its ordered stops (the list endpoint only carries the counts).
class TransportRoute {
  const TransportRoute({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.name,
    required this.label,
    required this.status,
    required this.vehicleId,
    required this.vehicleName,
    required this.vehicleRegistrationNumber,
    required this.capacity,
    required this.driverId,
    required this.driverName,
    required this.driverMobile,
    required this.stopsCount,
    required this.studentsCount,
    this.attendantUserId,
    this.attendantName,
    this.stops = const [],
    this.schoolLatitude,
    this.schoolLongitude,
    this.path = const RoutePath.notComputed(),
  });

  factory TransportRoute.fromJson(Map<String, dynamic> json) {
    return TransportRoute(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      name: json['name'] as String,
      label: json['label'] as String,
      status: TransportStatus.fromApiValue(json['status'] as String),
      vehicleId: json['vehicle_id'] as int?,
      vehicleName: json['vehicle_name'] as String?,
      vehicleRegistrationNumber: json['vehicle_registration_number'] as String?,
      capacity: json['capacity'] as int?,
      driverId: json['driver_id'] as int?,
      driverName: json['driver_name'] as String?,
      driverMobile: json['driver_mobile'] as String?,
      stopsCount: json['stops_count'] as int? ?? 0,
      studentsCount: json['students_count'] as int? ?? 0,
      attendantUserId: json['attendant_user_id'] as int?,
      attendantName: json['attendant_name'] as String?,
      stops: ((json['stops'] as List?) ?? const []).cast<Map<String, dynamic>>().map(TransportStop.fromJson).toList(),
      schoolLatitude: json['school_latitude'] as String?,
      schoolLongitude: json['school_longitude'] as String?,
      path: RoutePath.fromJson(json['path']),
    );
  }

  /// Where the route's school is, because the road ends there and the map
  /// draws it. Null for a school nobody has placed yet. Only on the detail
  /// view, like the stops.
  final String? schoolLatitude;
  final String? schoolLongitude;

  /// The road through the stops, as the server last worked it out.
  final RoutePath path;

  final int id;
  final int schoolId;
  final String? schoolName;
  final String name;

  /// "Bus 04 - Green Park" (or just the name when no vehicle is attached).
  final String label;
  final TransportStatus status;
  final int? vehicleId;
  final String? vehicleName;
  final String? vehicleRegistrationNumber;

  /// The vehicle's seat count; null when the route has no vehicle yet.
  final int? capacity;
  final int? driverId;
  final String? driverName;
  final String? driverMobile;
  final int stopsCount;
  final int studentsCount;

  /// The Bus Attendant who runs this route's trips - a user id, not a staff
  /// profile id. Null when nobody is assigned.
  final int? attendantUserId;
  final String? attendantName;
  final List<TransportStop> stops;

  bool get isActive => status == TransportStatus.active;

  bool get isFull => capacity != null && studentsCount >= capacity!;
}

/// One rider on a route - the "Students on Bus" row.
class RouteStudent {
  const RouteStudent({
    required this.studentId,
    required this.admissionNumber,
    required this.name,
    required this.classSectionName,
    required this.guardianName,
    required this.guardianMobile,
    required this.stopId,
    required this.stopName,
    required this.stopSequenceNumber,
  });

  factory RouteStudent.fromJson(Map<String, dynamic> json) {
    return RouteStudent(
      studentId: json['student_id'] as int,
      admissionNumber: json['admission_number'] as String,
      name: json['name'] as String,
      classSectionName: json['class_section_name'] as String?,
      guardianName: json['guardian_name'] as String,
      guardianMobile: json['guardian_mobile'] as String?,
      stopId: json['stop_id'] as int,
      stopName: json['stop_name'] as String,
      stopSequenceNumber: json['stop_sequence_number'] as int,
    );
  }

  final int studentId;
  final String admissionNumber;
  final String name;
  final String? classSectionName;
  final String guardianName;
  final String? guardianMobile;
  final int stopId;
  final String stopName;
  final int stopSequenceNumber;
}

/// The road a route follows, as the server last worked it out
/// (docs/maps.md, M2).
///
/// Four states rather than a line or nothing, because what the map should
/// draw differs in each: nothing to draw yet, the road, straight lines
/// while the road is being worked out, and straight lines with a reason and
/// a way to try again.
enum RoutePathStatus {
  /// Nothing has been computed - usually because the stops or the school
  /// have no coordinates yet.
  none,

  /// The stored line is the road through the stops as they stand.
  ok,

  /// The stops changed and the job has not run. The line, if there is one,
  /// is of where the stops used to be.
  stale,

  /// Google refused or could not be reached.
  failed;

  static RoutePathStatus fromApiValue(Object? value) {
    return switch (value) {
      'ok' => RoutePathStatus.ok,
      'stale' => RoutePathStatus.stale,
      'failed' => RoutePathStatus.failed,
      // Anything this build does not recognise is "no road", which draws
      // straight lines - the safe reading of a word from a newer server.
      _ => RoutePathStatus.none,
    };
  }
}

class RoutePath {
  const RoutePath({
    required this.status,
    required this.polyline,
    required this.distanceM,
    required this.durationS,
    required this.failureReason,
  });

  const RoutePath.notComputed()
    : status = RoutePathStatus.none,
      polyline = null,
      distanceM = null,
      durationS = null,
      failureReason = null;

  factory RoutePath.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const RoutePath.notComputed();

    final polyline = json['polyline'];

    return RoutePath(
      status: RoutePathStatus.fromApiValue(json['status']),
      polyline: polyline is String && polyline.isNotEmpty ? polyline : null,
      distanceM: json['distance_m'] as int?,
      durationS: json['duration_s'] as int?,
      failureReason: json['failure_reason'] as String?,
    );
  }

  final RoutePathStatus status;

  /// Google's encoded polyline. Null whenever there is no line to draw -
  /// including when the status is `ok` but the server sent nothing, which
  /// should not happen and must not draw a broken line if it does.
  final String? polyline;

  final int? distanceM;
  final int? durationS;
  final String? failureReason;

  /// Whether the drawn line is of where the stops are *now*.
  bool get isCurrent => status == RoutePathStatus.ok && polyline != null;

  /// Whether to say something about it. A road that is simply current needs
  /// no explanation.
  bool get needsExplaining => status != RoutePathStatus.ok;
}
