import '../../transport/data/models/transport_trip.dart';
import 'models/trip_mark.dart';

/// pending -> boarded or absent; boarded -> dropped; dropped and absent are
/// final. The server's rule (TripRiderStatus.can_become), so the phone never
/// offers a mark the server would turn down.
bool riderCanBecome(TripRiderStatus from, TripRiderStatus to) {
  return switch (from) {
    TripRiderStatus.pending => to == TripRiderStatus.boarded || to == TripRiderStatus.absent,
    TripRiderStatus.boarded => to == TripRiderStatus.dropped,
    TripRiderStatus.dropped || TripRiderStatus.absent => false,
  };
}

/// The trip as the attendant sees it: the server's last copy with the marks
/// still waiting to be sent laid on top, in the order they were made - which
/// is what makes every tap show at once, signal or not.
TransportTrip applyMarks(TransportTrip trip, Iterable<TripMark> marks) {
  var result = trip;
  for (final mark in marks) {
    if (mark.tripId == trip.id) result = applyMark(result, mark);
  }
  return result;
}

/// One mark on top of [trip]. A mark that no longer fits (the trip has
/// ended, the child was already dropped) changes nothing: the server will
/// say so when it arrives.
TransportTrip applyMark(TransportTrip trip, TripMark mark) {
  if (!trip.isInProgress) return trip;

  return switch (mark.type) {
    TripMarkType.stopReached => _reachStop(trip, mark.stopId),
    TripMarkType.boarded => _moveRider(trip, mark.studentId, TripRiderStatus.boarded),
    TripMarkType.dropped => _moveRider(trip, mark.studentId, TripRiderStatus.dropped),
    TripMarkType.absent => _moveRider(trip, mark.studentId, TripRiderStatus.absent),
    TripMarkType.guardianCalled => trip,
    TripMarkType.end => _end(trip),
  };
}

TransportTrip _reachStop(TransportTrip trip, int? stopId) {
  final index = trip.stops.indexWhere((s) => s.id == stopId);
  if (index < 0) return trip;

  final stop = trip.stops[index];
  final stops = [
    for (final s in trip.stops)
      s.id == stopId
          ? TripStop(
              id: s.id,
              name: s.name,
              sequenceNumber: s.sequenceNumber,
              pickupTime: s.pickupTime,
              dropTime: s.dropTime,
              reached: true,
            )
          : s,
  ];

  return trip.copyWith(
    currentStopId: stop.id,
    currentStopName: stop.name,
    stops: stops,
    stopsLeft: stops.where((s) => !s.reached).length,
  );
}

TransportTrip _moveRider(TransportTrip trip, int? studentId, TripRiderStatus status) {
  final riders = [
    for (final r in trip.riders)
      r.studentId == studentId && riderCanBecome(r.status, status) ? r.copyWith(status: status) : r,
  ];
  return _withCounts(trip, riders);
}

TransportTrip _end(TransportTrip trip) {
  // The server will not end a trip with somebody aboard; neither does this.
  if (trip.riders.any((r) => r.status == TripRiderStatus.boarded)) return trip;

  // Whoever never boarded is marked absent when the trip ends, as on the server.
  final riders = [
    for (final r in trip.riders) r.status == TripRiderStatus.pending ? r.copyWith(status: TripRiderStatus.absent) : r,
  ];
  return _withCounts(trip.copyWith(status: TripStatus.completed), riders);
}

TransportTrip _withCounts(TransportTrip trip, List<TripRider> riders) {
  int count(TripRiderStatus status) => riders.where((r) => r.status == status).length;

  return trip.copyWith(
    riders: riders,
    pendingCount: count(TripRiderStatus.pending),
    boardedCount: count(TripRiderStatus.boarded),
    droppedCount: count(TripRiderStatus.dropped),
    absentCount: count(TripRiderStatus.absent),
  );
}
