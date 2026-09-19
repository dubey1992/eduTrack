import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transport/data/models/transport_trip.dart';
import '../data/apply_marks.dart';
import '../data/models/trip_mark.dart';
import '../data/my_trip_repository.dart';
import '../data/phone_dialer.dart';
import 'trip_mark_queue.dart';

/// A trip as last heard from the server - or from the phone's copy of that,
/// when there was no signal.
class TripSnapshot {
  const TripSnapshot({required this.trip, this.fromCache = false});

  final TransportTrip trip;
  final bool fromCache;
}

final tripDetailProvider = AsyncNotifierProvider.autoDispose.family<TripDetailNotifier, TripSnapshot, int>(
  TripDetailNotifier.new,
);

/// The trip the attendant is running: what the server last said, and the
/// marks they make on it. Every mark goes into [tripMarkQueueProvider]; what
/// the screen shows is [myTripViewProvider], which lays the waiting marks on
/// top of this copy.
class TripDetailNotifier extends AsyncNotifier<TripSnapshot> {
  TripDetailNotifier(this.tripId);

  final int tripId;

  @override
  Future<TripSnapshot> build() async {
    final (trip, :fromCache) = await ref.read(myTripRepositoryProvider).trip(tripId);
    return TripSnapshot(trip: trip, fromCache: fromCache);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// The trip as a sync just returned it.
  void acceptServerCopy(TransportTrip trip) => state = AsyncData(TripSnapshot(trip: trip));

  /// The trip as shown, waiting marks included - worked out here rather than
  /// read from [myTripViewProvider], which is built on this notifier.
  TransportTrip? get _shown {
    final trip = state.value?.trip;
    return trip == null ? null : applyMarks(trip, ref.read(tripMarkQueueProvider).marksFor(tripId));
  }

  Future<void> reachStop(TripStop stop) async {
    final trip = _shown;
    if (trip == null || !trip.isInProgress || stop.reached) return;

    await _mark(TripMarkType.stopReached, 'Reached ${stop.name}', stopId: stop.id);
  }

  Future<void> markRider(TripRider rider, TripRiderStatus status) async {
    final trip = _shown;
    final current = trip?.riders.where((r) => r.studentId == rider.studentId).firstOrNull;
    if (trip == null || !trip.isInProgress || current == null || !riderCanBecome(current.status, status)) return;

    final type = switch (status) {
      TripRiderStatus.boarded => TripMarkType.boarded,
      TripRiderStatus.dropped => TripMarkType.dropped,
      TripRiderStatus.absent => TripMarkType.absent,
      TripRiderStatus.pending => throw ArgumentError('A rider is never marked back to pending.'),
    };
    await _mark(type, '${rider.name} ${status.label.toLowerCase()}', studentId: rider.studentId);
  }

  /// Opens the dialler with the guardian's number, and records that the call
  /// was made. Returns false when the dialler could not be opened.
  Future<bool> callParent(TripRider rider) async {
    final number = rider.guardianMobile;
    if (number == null || number.trim().isEmpty) return false;

    final opened = await ref.read(phoneDialerProvider).dial(number);
    if (opened) {
      await _mark(TripMarkType.guardianCalled, 'Called the parent of ${rider.name}', studentId: rider.studentId);
    }
    return opened;
  }

  /// Ends the trip. Not while anybody is still aboard - the server's rule.
  Future<void> end() async {
    final trip = _shown;
    if (trip == null || !trip.isInProgress || trip.riders.any((r) => r.status == TripRiderStatus.boarded)) return;

    await _mark(TripMarkType.end, 'End trip');
  }

  Future<void> _mark(TripMarkType type, String label, {int? stopId, int? studentId}) {
    final mark = TripMark.now(tripId: tripId, type: type, label: label, stopId: stopId, studentId: studentId);
    return ref.read(tripMarkQueueProvider.notifier).enqueue(mark);
  }
}

/// What the My Trip screen shows for a trip: the server's copy with every
/// mark still waiting to be sent applied on top.
final myTripViewProvider = Provider.autoDispose.family<AsyncValue<TripSnapshot>, int>((ref, tripId) {
  final snapshot = ref.watch(tripDetailProvider(tripId));
  final marks = ref.watch(tripMarkQueueProvider.select((queue) => queue.marksFor(tripId)));

  return snapshot.whenData((value) => TripSnapshot(trip: applyMarks(value.trip, marks), fromCache: value.fromCache));
});
