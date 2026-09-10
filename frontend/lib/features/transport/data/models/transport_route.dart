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
    this.stops = const [],
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
      stops: ((json['stops'] as List?) ?? const []).cast<Map<String, dynamic>>().map(TransportStop.fromJson).toList(),
    );
  }

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
