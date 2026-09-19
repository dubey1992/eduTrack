import '../../../transport/data/models/transport_trip.dart';

/// Reads a trip resource into the transport feature's [TransportTrip].
///
/// Timeline events of a kind that model does not know yet (a
/// `guardian_called` from Call Parent, for one) are left out rather than
/// failing the whole trip: My Trip does not show the timeline, and a bus
/// must never lose its rider list over a new kind of log line.
TransportTrip tripFromJson(Map<String, dynamic> json) {
  final known = {for (final type in TripEventType.values) type.apiValue};
  final events = (json['events'] as List?) ?? const [];

  return TransportTrip.fromJson({
    ...json,
    'events': [
      for (final event in events)
        if (event is Map<String, dynamic> && known.contains(event['type'])) event,
    ],
  });
}

/// A route this attendant runs, with today's pickup and drop trips if they
/// have started (GET /transport/my-routes).
class MyRoute {
  const MyRoute({
    required this.id,
    required this.name,
    required this.label,
    required this.vehicleName,
    required this.vehicleRegistrationNumber,
    required this.driverName,
    required this.stopsCount,
    required this.studentsCount,
    required this.pickup,
    required this.drop,
  });

  factory MyRoute.fromJson(Map<String, dynamic> json) {
    final today = (json['today'] as Map<String, dynamic>?) ?? const {};
    final pickup = today['pickup'];
    final drop = today['drop'];

    return MyRoute(
      id: json['id'] as int,
      name: json['name'] as String,
      label: json['label'] as String? ?? json['name'] as String,
      vehicleName: json['vehicle_name'] as String?,
      vehicleRegistrationNumber: json['vehicle_registration_number'] as String?,
      driverName: json['driver_name'] as String?,
      stopsCount: json['stops_count'] as int? ?? 0,
      studentsCount: json['students_count'] as int? ?? 0,
      pickup: pickup is Map<String, dynamic> ? tripFromJson(pickup) : null,
      drop: drop is Map<String, dynamic> ? tripFromJson(drop) : null,
    );
  }

  final int id;
  final String name;
  final String label;
  final String? vehicleName;
  final String? vehicleRegistrationNumber;
  final String? driverName;
  final int stopsCount;
  final int studentsCount;

  /// Today's trips, null when not started. A cancelled trip is not listed.
  final TransportTrip? pickup;
  final TransportTrip? drop;

  TransportTrip? tripFor(TripDirection direction) => direction == TripDirection.pickup ? pickup : drop;
}

/// The My Trip screen's opening page: the school's today and the routes.
class MyRoutesDay {
  const MyRoutesDay({required this.date, required this.routes, this.fromCache = false});

  factory MyRoutesDay.fromJson(Map<String, dynamic> json, {bool fromCache = false}) {
    return MyRoutesDay(
      date: json['date'] as String,
      routes: ((json['routes'] as List?) ?? const []).cast<Map<String, dynamic>>().map(MyRoute.fromJson).toList(),
      fromCache: fromCache,
    );
  }

  /// `yyyy-MM-dd`, the school's today.
  final String date;
  final List<MyRoute> routes;

  /// True when there was no signal and this is the copy last fetched.
  final bool fromCache;
}
