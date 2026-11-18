import '../../transport/data/models/transport_trip.dart';

/// A trip started on the phone with no signal (docs/mobile-apps-review.md,
/// 2.4), waiting for the server to start it for real.
///
/// Until then the trip goes by a stand-in id - negative, so it can never be
/// a server's - and everything the crew does on it (marks, the bus's
/// positions, End) is kept under that id. When the start gets through the
/// stand-in is mapped to the real trip, and what was waiting goes there.
class PendingStart {
  const PendingStart({required this.localId, required this.routeId, required this.direction, required this.startedAt});

  factory PendingStart.fromJson(Map<String, dynamic> json) => PendingStart(
    localId: json['local_id'] as int,
    routeId: json['route_id'] as int,
    direction: TripDirection.fromApiValue(json['direction'] as String),
    startedAt: json['started_at'] as String,
  );

  final int localId;
  final int routeId;
  final TripDirection direction;

  /// When Start was pressed - ISO 8601 in UTC, sent with the start so the
  /// marks made since are on the trip's own clock.
  final String startedAt;

  Map<String, dynamic> toJson() => {
    'local_id': localId,
    'route_id': routeId,
    'direction': direction.apiValue,
    'started_at': startedAt,
  };
}

/// The stand-in id of today's [direction] trip on [routeId]: negative, one
/// per route and direction. Starting again on another day reuses it, which
/// replaces the old stand-in rather than adding another.
int localTripId(int routeId, TripDirection direction) => -(routeId * 2 + (direction == TripDirection.pickup ? 0 : 1));

bool isLocalTrip(int tripId) => tripId < 0;

/// The trip as the phone shows it until the server has it, built from the
/// route's roster on the phone's copy of My routes: every child waiting,
/// no stop reached.
Map<String, dynamic> localTripJson({
  required Map<String, dynamic> route,
  required String date,
  required TripDirection direction,
  required PendingStart start,
}) {
  final roster = (route['roster'] as Map<String, dynamic>?) ?? const {};
  final riders = ((roster['riders'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final stops = ((roster['stops'] as List?) ?? const []).cast<Map<String, dynamic>>();

  return {
    'id': start.localId,
    'school_id': route['school_id'] ?? 0,
    'route_id': route['id'],
    'route_name': route['name'],
    'route_label': route['label'] ?? route['name'],
    'vehicle_id': route['vehicle_id'] ?? 0,
    'vehicle_name': route['vehicle_name'] ?? '',
    'vehicle_registration_number': route['vehicle_registration_number'] ?? '',
    'driver_id': route['driver_id'] ?? 0,
    'driver_name': route['driver_name'] ?? '',
    'driver_mobile': route['driver_mobile'],
    'trip_date': date,
    'direction': direction.apiValue,
    'status': 'in_progress',
    'current_stop_id': null,
    'current_stop_name': null,
    'started_by_name': null,
    'started_at': start.startedAt,
    'ended_at': null,
    'started_at_label': null,
    'ended_at_label': null,
    'riders_count': riders.length,
    'pending_count': riders.length,
    'boarded_count': 0,
    'dropped_count': 0,
    'absent_count': 0,
    'stops_left': stops.length,
    'stops': stops,
    'riders': riders,
    'events': const <Object>[],
  };
}
