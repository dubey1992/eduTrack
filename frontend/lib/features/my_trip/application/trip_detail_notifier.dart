import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transport/data/models/transport_trip.dart';
import '../data/apply_marks.dart';
import '../data/models/trip_mark.dart';
import '../data/my_trip_repository.dart';
import '../data/location_source.dart';
import '../data/phone_dialer.dart';
import '../data/trip_voice.dart';
import 'auto_reach.dart';
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

  /// [auto]: the phone saw the bus at the stop and marked it itself (M7).
  Future<void> reachStop(TripStop stop, {bool auto = false}) async {
    final trip = _shown;
    if (trip == null || !trip.isInProgress || stop.reached) return;

    await _mark(TripMarkType.stopReached, 'Reached ${stop.name}', stopId: stop.id, auto: auto);
    await announceNextStop();
  }

  /// A position the phone took: when the bus is at the next stop, it is
  /// marked Reached without a tap (docs/mobile-apps-review.md, M7, 1.3).
  /// Returns the stop it marked, if any.
  Future<TripStop?> autoReach(DevicePosition position) async {
    final trip = _shown;
    if (trip == null) return null;

    final stop = stopReachedByItself(trip, position);
    if (stop != null) await reachStop(stop, auto: true);
    return stop;
  }

  /// Says where the bus goes next, unless the crew has muted the prompts
  /// (M7, 3.2).
  Future<void> announceNextStop() async {
    final trip = _shown;
    if (trip == null || !ref.read(tripVoiceOnProvider)) return;

    final sentence = nextStopPrompt(trip);
    if (sentence != null) await ref.read(tripVoiceProvider).say(sentence);
  }

  /// "Running late" to the parents still waiting (M7, 5.5): 10, 15 or 30
  /// minutes. A mark like any other, so it waits on the phone without
  /// signal.
  Future<void> reportDelay(int minutes) async {
    final trip = _shown;
    if (trip == null || !trip.isInProgress || !delayChoices.contains(minutes)) return;

    await _mark(TripMarkType.delay, 'Running $minutes minutes late', minutes: minutes);
  }

  /// What "Running late" offers, and nothing else (decided 2026-11-24).
  static const delayChoices = [10, 15, 30];

  /// Marks [rider], held for [TripMarkQueue.undoWindow] so a wrong tap can
  /// be taken back. Returns the mark's id for [undoMark], or null when
  /// nothing was marked.
  Future<String?> markRider(TripRider rider, TripRiderStatus status) async {
    final trip = _shown;
    final current = trip?.riders.where((r) => r.studentId == rider.studentId).firstOrNull;
    if (trip == null || !trip.isInProgress || current == null || !riderCanBecome(current.status, status)) {
      return null;
    }

    final type = switch (status) {
      TripRiderStatus.boarded => TripMarkType.boarded,
      TripRiderStatus.dropped => TripMarkType.dropped,
      TripRiderStatus.absent => TripMarkType.absent,
      TripRiderStatus.pending => throw ArgumentError('A rider is never marked back to pending.'),
    };
    return _mark(
      type,
      '${rider.name} ${status.label.toLowerCase()}',
      studentId: rider.studentId,
      hold: TripMarkQueue.undoWindow,
    );
  }

  /// Takes back a rider mark inside its undo window; false once it is sent.
  Future<bool> undoMark(String clientId) => ref.read(tripMarkQueueProvider.notifier).undo(clientId);

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

  /// Asks the school for help. It changes nothing about the trip: the bus
  /// keeps running and the children stay marked (docs/driver-app.md, D5.2).
  Future<void> raiseSos() async {
    final trip = _shown;
    if (trip == null || !trip.isInProgress) return;

    await _mark(TripMarkType.sos, 'SOS sent to the school');
  }

  /// Ends the trip. Not while anybody is still aboard - the server's rule.
  Future<void> end() async {
    final trip = _shown;
    if (trip == null || !trip.isInProgress || trip.riders.any((r) => r.status == TripRiderStatus.boarded)) return;

    await _mark(TripMarkType.end, 'End trip');
  }

  Future<String> _mark(
    TripMarkType type,
    String label, {
    int? stopId,
    int? studentId,
    Duration? hold,
    bool auto = false,
    int? minutes,
  }) async {
    final mark = TripMark.now(
      tripId: tripId,
      type: type,
      label: label,
      stopId: stopId,
      studentId: studentId,
      auto: auto,
      minutes: minutes,
    );
    await ref.read(tripMarkQueueProvider.notifier).enqueue(mark, hold: hold);
    return mark.clientId;
  }
}

/// What the My Trip screen shows for a trip: the server's copy with every
/// mark still waiting to be sent applied on top.
final myTripViewProvider = Provider.autoDispose.family<AsyncValue<TripSnapshot>, int>((ref, tripId) {
  final snapshot = ref.watch(tripDetailProvider(tripId));
  final marks = ref.watch(tripMarkQueueProvider.select((queue) => queue.marksFor(tripId)));

  return snapshot.whenData((value) => TripSnapshot(trip: applyMarks(value.trip, marks), fromCache: value.fromCache));
});
