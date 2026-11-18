import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

/// A record, kept on the phone, of how location sharing went on the last
/// trips: every position kept, every batch sent or held, every time sharing
/// stopped and why, and every time the phone put the app in the background
/// (docs/mobile-apps-review.md, M0 - the real-phone GPS test).
///
/// It exists for one question nobody can answer from the office: *did this
/// phone keep reporting with its screen off?* Xiaomi, Oppo and Vivo stop
/// apps their own way, which no code can ask about - but a long gap between
/// two kept positions on a moving bus is exactly what that looks like. The
/// Trip check screen reads it, and its report can be shared.
///
/// Nothing personal is in it: times, counts and accuracies - no positions,
/// no names.
enum TripHealthKind { sharingOn, point, sent, waiting, refused, cleared, sharingOff, appPaused, appResumed }

@immutable
class TripHealthEvent {
  const TripHealthEvent({required this.at, required this.kind, this.tripId, this.count, this.detail});

  factory TripHealthEvent.fromJson(Map<String, dynamic> json) {
    return TripHealthEvent(
      at: DateTime.parse(json['at'] as String),
      kind: TripHealthKind.values.byName(json['kind'] as String),
      tripId: json['trip'] as int?,
      count: json['n'] as int?,
      detail: json['d'] as String?,
    );
  }

  final DateTime at;
  final TripHealthKind kind;
  final int? tripId;

  /// Points sent or waiting, or a fix's accuracy in metres.
  final int? count;
  final String? detail;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'kind': kind.name,
    'trip': ?tripId,
    'n': ?count,
    'd': ?detail,
  };
}

/// What the last trip's log adds up to - the figures the Trip check shows.
class TripHealthSummary {
  const TripHealthSummary({
    required this.tripId,
    required this.from,
    required this.to,
    required this.points,
    required this.longestGap,
    required this.longestGapAt,
    required this.sent,
    required this.stillWaiting,
    required this.refused,
    required this.cleared,
    required this.backgrounded,
    required this.stops,
  });

  /// The most recent trip in [events], or null when none shared a position.
  static TripHealthSummary? of(List<TripHealthEvent> events) {
    final tripIds = events.map((event) => event.tripId).whereType<int>();
    if (tripIds.isEmpty) return null;

    final tripId = tripIds.last;
    final first = events.indexWhere((event) => event.tripId == tripId);
    final ofTrip = events.sublist(first);
    final points = ofTrip.where((event) => event.kind == TripHealthKind.point && event.tripId == tripId).toList();

    var longest = Duration.zero;
    DateTime? longestAt;
    for (var i = 1; i < points.length; i++) {
      final gap = points[i].at.difference(points[i - 1].at);
      if (gap > longest) {
        longest = gap;
        longestAt = points[i - 1].at;
      }
    }

    int total(TripHealthKind kind) =>
        ofTrip.where((event) => event.kind == kind && event.tripId == tripId).fold(0, (sum, e) => sum + (e.count ?? 0));

    final waiting = ofTrip.lastWhere(
      (event) => event.tripId == tripId && (event.kind == TripHealthKind.waiting || event.kind == TripHealthKind.sent),
      orElse: () => TripHealthEvent(at: ofTrip.first.at, kind: TripHealthKind.sent),
    );

    return TripHealthSummary(
      tripId: tripId,
      from: ofTrip.first.at,
      to: ofTrip.last.at,
      points: points.length,
      longestGap: longest,
      longestGapAt: longestAt,
      sent: total(TripHealthKind.sent),
      stillWaiting: waiting.kind == TripHealthKind.waiting ? waiting.count ?? 0 : 0,
      refused: total(TripHealthKind.refused),
      cleared: total(TripHealthKind.cleared),
      backgrounded: ofTrip.where((event) => event.kind == TripHealthKind.appPaused).length,
      stops: [
        for (final event in ofTrip)
          if (event.kind == TripHealthKind.sharingOff && event.detail != null) event.detail!,
      ],
    );
  }

  final int tripId;
  final DateTime from;
  final DateTime to;
  final int points;

  /// The longest time between two kept positions. The app keeps one at
  /// least every minute while sharing (the heartbeat), so anything much
  /// longer means the phone stopped it.
  final Duration longestGap;
  final DateTime? longestGapAt;
  final int sent;
  final int stillWaiting;
  final int refused;

  /// Points dropped because the server said the trip had ended.
  final int cleared;

  /// Times the app went to the background during the trip.
  final int backgrounded;

  /// Why sharing stopped, in order.
  final List<String> stops;

  /// A gap this long on a run means the phone paused the app.
  static const worryingGap = Duration(minutes: 3);

  bool get hadWorryingGap => longestGap >= worryingGap;
}

final tripHealthLogProvider = Provider<TripHealthLog>((ref) => TripHealthLog(ref.watch(keyValueStoreProvider)));

class TripHealthLog {
  TripHealthLog(this._store);

  final KeyValueStore _store;

  static const _key = 'trip_health_log';

  /// About three runs at the fastest cadence; older events fall off.
  static const keep = 600;

  List<TripHealthEvent>? _events;

  Future<List<TripHealthEvent>> events() async {
    if (_events != null) return List.unmodifiable(_events!);

    try {
      final raw = await _store.read(_key);
      final list = raw == null ? const [] : jsonDecode(raw) as List<dynamic>;
      _events = [for (final item in list) TripHealthEvent.fromJson(item as Map<String, dynamic>)];
    } on Object catch (error) {
      // A log that cannot be read is started again rather than allowed to
      // stop the trip it exists to watch.
      debugPrint('Trip log unreadable, starting again: $error');
      _events = [];
    }

    return List.unmodifiable(_events!);
  }

  /// Adds one event. Never throws: a trip must not fail because its log did.
  Future<void> add(TripHealthKind kind, {int? tripId, int? count, String? detail}) async {
    try {
      final events = [...await this.events()];
      events.add(TripHealthEvent(at: DateTime.now(), kind: kind, tripId: tripId, count: count, detail: detail));
      _events = events.length > keep ? events.sublist(events.length - keep) : events;
      await _store.write(_key, jsonEncode([for (final event in _events!) event.toJson()]));
    } on Object catch (error) {
      debugPrint('Trip log not written: $error');
    }
  }

  Future<void> clear() async {
    _events = [];
    try {
      await _store.delete(_key);
    } on Object catch (error) {
      debugPrint('Trip log not cleared: $error');
    }
  }
}
