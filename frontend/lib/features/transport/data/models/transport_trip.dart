enum TripDirection {
  pickup('pickup', 'Pickup'),
  drop('drop', 'Drop');

  const TripDirection(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static TripDirection fromApiValue(String value) => TripDirection.values.firstWhere((d) => d.apiValue == value);
}

enum TripStatus {
  inProgress('in_progress', 'En Route'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const TripStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static TripStatus fromApiValue(String value) => TripStatus.values.firstWhere((s) => s.apiValue == value);
}

/// pending -> boarded -> dropped, or pending -> absent; never backwards.
enum TripRiderStatus {
  pending('pending', 'Pending'),
  boarded('boarded', 'Boarded'),
  dropped('dropped', 'Dropped'),
  absent('absent', 'Absent');

  const TripRiderStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static TripRiderStatus fromApiValue(String value) => TripRiderStatus.values.firstWhere((s) => s.apiValue == value);
}

enum TripEventType {
  started('started'),
  stopReached('stop_reached'),
  boarded('boarded'),
  dropped('dropped'),
  absent('absent'),
  completed('completed'),
  cancelled('cancelled');

  const TripEventType(this.apiValue);

  final String apiValue;

  static TripEventType fromApiValue(String value) => TripEventType.values.firstWhere((t) => t.apiValue == value);
}

class TripStop {
  const TripStop({
    required this.id,
    required this.name,
    required this.sequenceNumber,
    required this.pickupTime,
    required this.dropTime,
    required this.reached,
  });

  factory TripStop.fromJson(Map<String, dynamic> json) {
    return TripStop(
      id: json['id'] as int,
      name: json['name'] as String,
      sequenceNumber: json['sequence_number'] as int,
      pickupTime: json['pickup_time'] as String?,
      dropTime: json['drop_time'] as String?,
      reached: json['reached'] as bool,
    );
  }

  final int id;
  final String name;
  final int sequenceNumber;
  final String? pickupTime;
  final String? dropTime;
  final bool reached;
}

class TripRider {
  const TripRider({
    required this.studentId,
    required this.admissionNumber,
    required this.name,
    required this.classSectionName,
    required this.guardianName,
    required this.guardianMobile,
    required this.stopId,
    required this.stopName,
    required this.stopSequenceNumber,
    required this.status,
    required this.boardedAt,
    required this.droppedAt,
    this.boardedAtLabel,
    this.droppedAtLabel,
  });

  factory TripRider.fromJson(Map<String, dynamic> json) {
    return TripRider(
      studentId: json['student_id'] as int,
      admissionNumber: json['admission_number'] as String,
      name: json['name'] as String,
      classSectionName: json['class_section_name'] as String?,
      guardianName: json['guardian_name'] as String,
      guardianMobile: json['guardian_mobile'] as String?,
      stopId: json['stop_id'] as int?,
      stopName: json['stop_name'] as String,
      stopSequenceNumber: json['stop_sequence_number'] as int,
      status: TripRiderStatus.fromApiValue(json['status'] as String),
      boardedAt: json['boarded_at'] as String?,
      droppedAt: json['dropped_at'] as String?,
      boardedAtLabel: json['boarded_at_label'] as String?,
      droppedAtLabel: json['dropped_at_label'] as String?,
    );
  }

  final int studentId;
  final String admissionNumber;
  final String name;
  final String? classSectionName;
  final String guardianName;
  final String? guardianMobile;
  final int? stopId;
  final String stopName;
  final int stopSequenceNumber;
  final TripRiderStatus status;
  final String? boardedAt;
  final String? droppedAt;

  /// Rendered by the API in the school's timezone. The raw instants above
  /// are UTC and must never be formatted in the browser's own zone.
  final String? boardedAtLabel;
  final String? droppedAtLabel;

  TripRider copyWith({
    TripRiderStatus? status,
    String? boardedAt,
    String? droppedAt,
    String? boardedAtLabel,
    String? droppedAtLabel,
  }) {
    return TripRider(
      studentId: studentId,
      admissionNumber: admissionNumber,
      name: name,
      classSectionName: classSectionName,
      guardianName: guardianName,
      guardianMobile: guardianMobile,
      stopId: stopId,
      stopName: stopName,
      stopSequenceNumber: stopSequenceNumber,
      status: status ?? this.status,
      boardedAt: boardedAt ?? this.boardedAt,
      droppedAt: droppedAt ?? this.droppedAt,
      boardedAtLabel: boardedAtLabel ?? this.boardedAtLabel,
      droppedAtLabel: droppedAtLabel ?? this.droppedAtLabel,
    );
  }
}

class TripEvent {
  const TripEvent({
    required this.id,
    required this.type,
    required this.stopId,
    required this.stopName,
    required this.studentId,
    required this.studentName,
    required this.recordedByName,
    required this.recordedAt,
    this.recordedAtLabel,
    required this.note,
  });

  factory TripEvent.fromJson(Map<String, dynamic> json) {
    return TripEvent(
      id: json['id'] as int,
      type: TripEventType.fromApiValue(json['type'] as String),
      stopId: json['stop_id'] as int?,
      stopName: json['stop_name'] as String?,
      studentId: json['student_id'] as int?,
      studentName: json['student_name'] as String?,
      recordedByName: json['recorded_by_name'] as String?,
      recordedAt: json['recorded_at'] as String,
      recordedAtLabel: json['recorded_at_label'] as String?,
      note: json['note'] as String?,
    );
  }

  final int id;
  final TripEventType type;
  final int? stopId;
  final String? stopName;
  final int? studentId;
  final String? studentName;
  final String? recordedByName;
  final String recordedAt;

  /// Rendered by the API in the school's timezone.
  final String? recordedAtLabel;
  final String? note;

  /// The timeline line for this event.
  String get description => switch (type) {
    TripEventType.started => note ?? 'Trip started',
    TripEventType.stopReached => 'Bus reached ${stopName ?? 'a stop'}',
    TripEventType.boarded => '${studentName ?? 'A student'} boarded${stopName == null ? '' : ' at $stopName'}',
    TripEventType.dropped => '${studentName ?? 'A student'} dropped off${stopName == null ? '' : ' at $stopName'}',
    TripEventType.absent => '${studentName ?? 'A student'} marked absent',
    TripEventType.completed => note ?? 'Trip completed',
    TripEventType.cancelled => note ?? 'Trip cancelled',
  };
}

/// One run of a route. The list endpoint carries the header fields and
/// [ridersCount]; the detail adds counts, stops, riders and the timeline.
class TransportTrip {
  const TransportTrip({
    required this.id,
    required this.schoolId,
    required this.routeId,
    required this.routeName,
    required this.routeLabel,
    required this.vehicleId,
    required this.vehicleName,
    required this.vehicleRegistrationNumber,
    required this.driverId,
    required this.driverName,
    required this.driverMobile,
    required this.tripDate,
    required this.direction,
    required this.status,
    required this.currentStopId,
    required this.currentStopName,
    required this.startedByName,
    required this.startedAt,
    required this.endedAt,
    this.startedAtLabel,
    this.endedAtLabel,
    required this.ridersCount,
    this.pendingCount,
    this.boardedCount,
    this.droppedCount,
    this.absentCount,
    this.stopsLeft,
    this.stops = const [],
    this.riders = const [],
    this.events = const [],
  });

  factory TransportTrip.fromJson(Map<String, dynamic> json) {
    return TransportTrip(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      routeId: json['route_id'] as int,
      routeName: json['route_name'] as String,
      routeLabel: json['route_label'] as String,
      vehicleId: json['vehicle_id'] as int,
      vehicleName: json['vehicle_name'] as String,
      vehicleRegistrationNumber: json['vehicle_registration_number'] as String,
      driverId: json['driver_id'] as int,
      driverName: json['driver_name'] as String,
      driverMobile: json['driver_mobile'] as String?,
      tripDate: json['trip_date'] as String,
      direction: TripDirection.fromApiValue(json['direction'] as String),
      status: TripStatus.fromApiValue(json['status'] as String),
      currentStopId: json['current_stop_id'] as int?,
      currentStopName: json['current_stop_name'] as String?,
      startedByName: json['started_by_name'] as String?,
      startedAt: json['started_at'] as String,
      endedAt: json['ended_at'] as String?,
      startedAtLabel: json['started_at_label'] as String?,
      endedAtLabel: json['ended_at_label'] as String?,
      ridersCount: json['riders_count'] as int,
      pendingCount: json['pending_count'] as int?,
      boardedCount: json['boarded_count'] as int?,
      droppedCount: json['dropped_count'] as int?,
      absentCount: json['absent_count'] as int?,
      stopsLeft: json['stops_left'] as int?,
      stops: ((json['stops'] as List?) ?? const []).cast<Map<String, dynamic>>().map(TripStop.fromJson).toList(),
      riders: ((json['riders'] as List?) ?? const []).cast<Map<String, dynamic>>().map(TripRider.fromJson).toList(),
      events: ((json['events'] as List?) ?? const []).cast<Map<String, dynamic>>().map(TripEvent.fromJson).toList(),
    );
  }

  final int id;
  final int schoolId;
  final int routeId;
  final String routeName;
  final String routeLabel;
  final int vehicleId;
  final String vehicleName;
  final String vehicleRegistrationNumber;
  final int driverId;
  final String driverName;
  final String? driverMobile;

  /// `yyyy-MM-dd`.
  final String tripDate;
  final TripDirection direction;
  final TripStatus status;
  final int? currentStopId;
  final String? currentStopName;
  final String? startedByName;
  final String startedAt;
  final String? endedAt;

  /// Rendered by the API in the school's timezone.
  final String? startedAtLabel;
  final String? endedAtLabel;
  final int ridersCount;
  final int? pendingCount;
  final int? boardedCount;
  final int? droppedCount;
  final int? absentCount;
  final int? stopsLeft;
  final List<TripStop> stops;
  final List<TripRider> riders;
  final List<TripEvent> events;

  bool get isInProgress => status == TripStatus.inProgress;

  TransportTrip copyWith({
    TripStatus? status,
    int? currentStopId,
    String? currentStopName,
    String? endedAt,
    String? endedAtLabel,
    int? pendingCount,
    int? boardedCount,
    int? droppedCount,
    int? absentCount,
    int? stopsLeft,
    List<TripStop>? stops,
    List<TripRider>? riders,
    List<TripEvent>? events,
  }) {
    return TransportTrip(
      id: id,
      schoolId: schoolId,
      routeId: routeId,
      routeName: routeName,
      routeLabel: routeLabel,
      vehicleId: vehicleId,
      vehicleName: vehicleName,
      vehicleRegistrationNumber: vehicleRegistrationNumber,
      driverId: driverId,
      driverName: driverName,
      driverMobile: driverMobile,
      tripDate: tripDate,
      direction: direction,
      status: status ?? this.status,
      currentStopId: currentStopId ?? this.currentStopId,
      currentStopName: currentStopName ?? this.currentStopName,
      startedByName: startedByName,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      startedAtLabel: startedAtLabel,
      endedAtLabel: endedAtLabel ?? this.endedAtLabel,
      ridersCount: ridersCount,
      pendingCount: pendingCount ?? this.pendingCount,
      boardedCount: boardedCount ?? this.boardedCount,
      droppedCount: droppedCount ?? this.droppedCount,
      absentCount: absentCount ?? this.absentCount,
      stopsLeft: stopsLeft ?? this.stopsLeft,
      stops: stops ?? this.stops,
      riders: riders ?? this.riders,
      events: events ?? this.events,
    );
  }
}
