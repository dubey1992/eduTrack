import '../../../core/utils/geo.dart';
import '../../transport/data/models/transport_trip.dart';
import '../data/location_source.dart';

/// The stop the bus has just reached by itself, or null (docs/mobile-apps-
/// review.md, M7, 1.3).
///
/// Only ever the next stop not yet reached - the one the crew is driving to -
/// and only when:
/// - the school has the distance switched on (`autoReachM` above 0);
/// - the stop has a pin;
/// - the fix is real and good enough to tell: not a mocked position, and no
///   less accurate than the distance itself (or [minAccuracyMetres], when
///   the distance is very short).
///
/// The Reached button stays for a stop with no pin or a bad fix.
TripStop? stopReachedByItself(TransportTrip trip, DevicePosition position) {
  final distance = trip.autoReachM;
  if (!trip.isInProgress || distance <= 0 || position.isMocked) return null;
  if (position.accuracy > (distance > minAccuracyMetres ? distance : minAccuracyMetres)) return null;

  final stops = [...trip.stops]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  final next = stops.where((stop) => !stop.reached).firstOrNull;
  if (next == null) return null;

  final latitude = double.tryParse(next.latitude ?? '');
  final longitude = double.tryParse(next.longitude ?? '');
  if (latitude == null || longitude == null) return null;

  final away = metresBetween(position.latitude, position.longitude, latitude, longitude);

  return away <= distance ? next : null;
}

/// A phone's fix is rarely better than this in a street; a tighter distance
/// still trusts a fix this good.
const minAccuracyMetres = 30.0;

/// What the phone says aloud as the bus heads for its next stop (M7, 3.2):
/// "Next stop Green Park, 4 children to pick up." Null when there is nothing
/// left to say.
String? nextStopPrompt(TransportTrip trip) {
  if (!trip.isInProgress) return null;

  final stops = [...trip.stops]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  final next = stops.where((stop) => !stop.reached).firstOrNull;
  if (next == null) return 'That was the last stop.';

  final pickup = trip.direction == TripDirection.pickup;
  final waiting = trip.riders
      .where((r) => r.stopId == next.id && r.status == (pickup ? TripRiderStatus.pending : TripRiderStatus.boarded))
      .length;
  final children = waiting == 1 ? '1 child' : '$waiting children';

  if (waiting == 0) return 'Next stop ${next.name}.';

  return 'Next stop ${next.name}, $children to ${pickup ? 'pick up' : 'drop off'}.';
}
