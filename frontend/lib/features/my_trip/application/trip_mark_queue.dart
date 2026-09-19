import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../data/models/not_sent_mark.dart';
import '../data/models/trip_mark.dart';
import '../data/my_trip_repository.dart';
import '../data/trip_offline_store.dart';
import 'trip_detail_notifier.dart';

/// The marks waiting to be sent, the ones the server turned down, and
/// whether sending is going on or failing for want of signal.
class TripMarkQueueState {
  const TripMarkQueueState({
    this.pending = const [],
    this.notSent = const [],
    this.sending = false,
    this.offline = false,
  });

  /// Oldest first - the order they are sent in.
  final List<TripMark> pending;
  final List<NotSentMark> notSent;
  final bool sending;

  /// The last attempt could not reach the server.
  final bool offline;

  int get pendingCount => pending.length;

  List<TripMark> marksFor(int tripId) => pending.where((m) => m.tripId == tripId).toList();

  List<NotSentMark> notSentFor(int tripId) => notSent.where((m) => m.tripId == tripId).toList();

  TripMarkQueueState copyWith({List<TripMark>? pending, List<NotSentMark>? notSent, bool? sending, bool? offline}) {
    return TripMarkQueueState(
      pending: pending ?? this.pending,
      notSent: notSent ?? this.notSent,
      sending: sending ?? this.sending,
      offline: offline ?? this.offline,
    );
  }
}

final tripMarkQueueProvider = NotifierProvider<TripMarkQueue, TripMarkQueueState>(TripMarkQueue.new);

/// The on-device queue of trip marks (docs/maps.md, "Offline").
///
/// Every mark is saved on the phone before anything else, so a tap shows at
/// once and survives the app being closed. Sending starts straight away and
/// goes oldest first; with no signal it is tried again after 5, 15, 30 and
/// then every 60 seconds, and again whenever the app comes back to the front.
/// Each mark's own id makes a resend harmless on the server.
class TripMarkQueue extends Notifier<TripMarkQueueState> {
  /// How long to wait before trying again, after 1, 2, 3, 4+ failures.
  static const retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// The most the sync endpoint takes in one request.
  static const maxBatch = 200;

  Timer? _retryTimer;
  int _failures = 0;
  late Future<void> _loaded;

  TripOfflineStore get _store => ref.read(tripOfflineStoreProvider);

  @override
  TripMarkQueueState build() {
    ref.onDispose(() => _retryTimer?.cancel());
    _loaded = _load();
    return const TripMarkQueueState();
  }

  /// Picks up whatever an earlier run of the app left unsent, and sends it.
  Future<void> _load() async {
    final pending = await _store.readMarks();
    final notSent = await _store.readNotSent();
    if (!ref.mounted) return;

    state = state.copyWith(pending: [...pending, ...state.pending], notSent: [...notSent, ...state.notSent]);
    if (pending.isNotEmpty) unawaited(flush());
  }

  /// Saves [mark] on the phone and starts sending it.
  Future<void> enqueue(TripMark mark) async {
    await _loaded;
    if (!ref.mounted) return;

    state = state.copyWith(pending: [...state.pending, mark]);
    await _store.saveMarks(state.pending);
    unawaited(flush());
  }

  /// Tries now rather than waiting out the back-off - the app came back to
  /// the front, or the attendant opened the trip.
  Future<void> retryNow() async {
    _retryTimer?.cancel();
    _failures = 0;
    await flush();
  }

  /// Sends everything waiting, oldest first, one trip's batch at a time.
  Future<void> flush() async {
    await _loaded;
    if (!ref.mounted || state.sending || state.pending.isEmpty) return;

    _retryTimer?.cancel();
    state = state.copyWith(sending: true);

    try {
      while (ref.mounted && state.pending.isNotEmpty) {
        final tripId = state.pending.first.tripId;
        final batch = state.pending.where((m) => m.tripId == tripId).take(maxBatch).toList();
        await _send(tripId, batch);
      }
      _failures = 0;
      if (ref.mounted) state = state.copyWith(sending: false, offline: false);
    } on Failure catch (failure) {
      if (!failure.isOffline) debugPrint('Sending trip marks failed: ${failure.code}');
      _scheduleRetry();
    } catch (error) {
      // A bug, not a lost signal - but the marks are still worth keeping.
      debugPrint('Sending trip marks failed unexpectedly: $error');
      _scheduleRetry();
    }
  }

  /// One batch for one trip. A batch the server refuses outright (a trip
  /// that is gone, or not this attendant's) cannot succeed by retrying, so
  /// its marks move to "not sent" with the server's reason.
  Future<void> _send(int tripId, List<TripMark> batch) async {
    try {
      final outcome = await ref.read(myTripRepositoryProvider).sync(tripId, batch);
      if (!ref.mounted) return;

      final results = {for (final r in outcome.results) r.clientId: r};
      final rejected = [
        for (final mark in batch)
          if (results[mark.clientId]?.status != MarkResultStatus.applied &&
              results[mark.clientId]?.status != MarkResultStatus.duplicate)
            NotSentMark(
              clientId: mark.clientId,
              tripId: tripId,
              label: mark.label,
              reason: results[mark.clientId]?.reason ?? 'The server did not record this mark.',
            ),
      ];

      await _settle(batch, rejected);

      final detail = tripDetailProvider(tripId);
      if (ref.exists(detail)) ref.read(detail.notifier).acceptServerCopy(outcome.trip);
    } on Failure catch (failure) {
      if (failure.isOffline) rethrow;
      if (!ref.mounted) return;
      await _settle(batch, [
        for (final mark in batch)
          NotSentMark(clientId: mark.clientId, tripId: tripId, label: mark.label, reason: failure.message),
      ]);
    }
  }

  /// Takes [batch] out of the queue, keeping [rejected] to be read.
  Future<void> _settle(List<TripMark> batch, List<NotSentMark> rejected) async {
    final sent = {for (final mark in batch) mark.clientId};
    state = state.copyWith(
      pending: state.pending.where((m) => !sent.contains(m.clientId)).toList(),
      notSent: [...state.notSent, ...rejected],
    );
    await _store.saveMarks(state.pending);
    if (rejected.isNotEmpty) await _store.saveNotSent(state.notSent);
  }

  void _scheduleRetry() {
    if (!ref.mounted) return;

    _failures++;
    state = state.copyWith(sending: false, offline: true);

    final delay = retryDelays[min(_failures, retryDelays.length) - 1];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, flush);
  }

  /// How many marks have not reached the server, once whatever an earlier
  /// run of the app left on the phone has been read - what signing out asks
  /// about, possibly before My Trip was ever opened this time.
  Future<int> waitingCount() async {
    await _loaded;
    return ref.mounted ? state.pendingCount : 0;
  }

  /// The attendant has read a turned-down mark.
  Future<void> dismissNotSent(String clientId) async {
    state = state.copyWith(notSent: state.notSent.where((m) => m.clientId != clientId).toList());
    await _store.saveNotSent(state.notSent);
  }

  /// Forgets everything on this phone - on sign-out, after the attendant
  /// agreed that unsent marks would be lost.
  Future<void> discardAll() async {
    await _loaded;
    _retryTimer?.cancel();
    _failures = 0;
    if (ref.mounted) state = const TripMarkQueueState();
    await _store.clear();
  }
}
