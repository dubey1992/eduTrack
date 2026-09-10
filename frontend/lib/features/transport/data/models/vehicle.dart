import 'transport_status.dart';

class Vehicle {
  const Vehicle({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.name,
    required this.registrationNumber,
    required this.capacity,
    required this.status,
    required this.routeId,
    required this.routeName,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      name: json['name'] as String,
      registrationNumber: json['registration_number'] as String,
      capacity: json['capacity'] as int,
      status: TransportStatus.fromApiValue(json['status'] as String),
      routeId: json['route_id'] as int?,
      routeName: json['route_name'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final String name;
  final String registrationNumber;
  final int capacity;
  final TransportStatus status;

  /// The route this vehicle currently serves, if any.
  final int? routeId;
  final String? routeName;

  bool get isActive => status == TransportStatus.active;
}
