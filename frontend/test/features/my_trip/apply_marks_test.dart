import 'package:edutrack_app/features/my_trip/data/apply_marks.dart';
import 'package:edutrack_app/features/my_trip/data/models/my_route.dart';
import 'package:edutrack_app/features/my_trip/data/models/trip_mark.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/my_trip_fixtures.dart';

TripMark _mark(TripMarkType type, {int tripId = 55, int? stopId, int? studentId}) =>
    TripMark.now(tripId: tripId, type: type, label: type.apiValue, stopId: stopId, studentId: studentId);

TripRiderStatus _statusOf(TransportTrip trip, int studentId) =>
    trip.riders.firstWhere((r) => r.studentId == studentId).status;

void main() {
  final trip = tripFromJson(tripJson());

  group('reading a trip', () {
    test('leaves out timeline events of a kind the app does not know, and keeps the rest', () {
      expect(trip.riders, hasLength(3));
      expect(trip.stops, hasLength(2));
      expect(trip.events.single.type, TripEventType.started);
    });
  });

  group('riderCanBecome mirrors the server', () {
    test('pending boards or is absent', () {
      expect(riderCanBecome(TripRiderStatus.pending, TripRiderStatus.boarded), isTrue);
      expect(riderCanBecome(TripRiderStatus.pending, TripRiderStatus.absent), isTrue);
      expect(riderCanBecome(TripRiderStatus.pending, TripRiderStatus.dropped), isFalse);
    });

    test('boarded can only be dropped; dropped and absent are final', () {
      expect(riderCanBecome(TripRiderStatus.boarded, TripRiderStatus.dropped), isTrue);
      expect(riderCanBecome(TripRiderStatus.boarded, TripRiderStatus.absent), isFalse);
      expect(riderCanBecome(TripRiderStatus.dropped, TripRiderStatus.boarded), isFalse);
      expect(riderCanBecome(TripRiderStatus.absent, TripRiderStatus.boarded), isFalse);
    });
  });

  group('applyMarks', () {
    test('a reached stop is marked and becomes the current stop', () {
      final shown = applyMarks(trip, [_mark(TripMarkType.stopReached, stopId: 101)]);

      expect(shown.stops.firstWhere((s) => s.id == 101).reached, isTrue);
      expect(shown.stops.firstWhere((s) => s.id == 102).reached, isFalse);
      expect(shown.currentStopId, 101);
      expect(shown.currentStopName, 'Main Gate');
      expect(shown.stopsLeft, 1);
    });

    test('boarded then dropped moves the child along, in order, and keeps the counts', () {
      final shown = applyMarks(trip, [
        _mark(TripMarkType.boarded, studentId: 1),
        _mark(TripMarkType.absent, studentId: 2),
        _mark(TripMarkType.dropped, studentId: 1),
      ]);

      expect(_statusOf(shown, 1), TripRiderStatus.dropped);
      expect(_statusOf(shown, 2), TripRiderStatus.absent);
      expect(shown.droppedCount, 1);
      expect(shown.absentCount, 1);
      expect(shown.pendingCount, 1);
    });

    test('a mark the child can no longer take changes nothing', () {
      final shown = applyMarks(trip, [
        _mark(TripMarkType.absent, studentId: 1),
        _mark(TripMarkType.boarded, studentId: 1),
        _mark(TripMarkType.dropped, studentId: 2),
      ]);

      expect(_statusOf(shown, 1), TripRiderStatus.absent);
      expect(_statusOf(shown, 2), TripRiderStatus.pending);
    });

    test('marks for another trip are ignored', () {
      final shown = applyMarks(trip, [_mark(TripMarkType.boarded, tripId: 99, studentId: 1)]);

      expect(_statusOf(shown, 1), TripRiderStatus.pending);
    });

    test('ending completes the trip and marks whoever never boarded absent', () {
      final shown = applyMarks(trip, [
        _mark(TripMarkType.boarded, studentId: 1),
        _mark(TripMarkType.dropped, studentId: 1),
        _mark(TripMarkType.end),
      ]);

      expect(shown.status, TripStatus.completed);
      expect(_statusOf(shown, 1), TripRiderStatus.dropped);
      expect(_statusOf(shown, 2), TripRiderStatus.absent);
      expect(_statusOf(shown, 3), TripRiderStatus.absent);
    });

    test('a trip is not ended with somebody aboard', () {
      final shown = applyMarks(trip, [_mark(TripMarkType.boarded, studentId: 1), _mark(TripMarkType.end)]);

      expect(shown.status, TripStatus.inProgress);
    });

    test('nothing changes a trip that has already ended', () {
      final ended = tripFromJson(tripJson(status: 'completed'));
      final shown = applyMarks(ended, [_mark(TripMarkType.boarded, studentId: 1)]);

      expect(_statusOf(shown, 1), TripRiderStatus.pending);
    });

    test('calling a parent changes nothing on the trip', () {
      final shown = applyMarks(trip, [_mark(TripMarkType.guardianCalled, studentId: 1)]);

      expect(_statusOf(shown, 1), TripRiderStatus.pending);
      expect(shown.status, TripStatus.inProgress);
    });
  });

  group('a mark', () {
    test('is sent with its id, kind, time and target - never its label or trip', () {
      final mark = _mark(TripMarkType.boarded, studentId: 1);
      final sent = mark.toSyncJson();

      expect(sent.keys, unorderedEquals(['client_id', 'type', 'occurred_at', 'student_id']));
      expect(sent['type'], 'boarded');
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(sent['client_id'] as String), isTrue);
      // UTC with its zone - the server refuses a time without one.
      expect((sent['occurred_at'] as String).endsWith('Z'), isTrue);
    });

    test('ids are unique', () {
      final ids = {for (var i = 0; i < 500; i++) TripMark.newClientId()};
      expect(ids, hasLength(500));
    });

    test('survives being stored and read back', () {
      final mark = _mark(TripMarkType.stopReached, stopId: 101);
      final back = TripMark.fromJson(mark.toJson());

      expect(back.clientId, mark.clientId);
      expect(back.tripId, 55);
      expect(back.type, TripMarkType.stopReached);
      expect(back.stopId, 101);
      expect(back.occurredAt, mark.occurredAt);
      expect(back.label, mark.label);
    });
  });
}
