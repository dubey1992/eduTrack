import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../my_trip/data/location_source.dart';
import '../data/check_in_repository.dart';
import '../data/models/my_attendance_day.dart';

/// No automatic retry, for the reason Today has none: the card offers its
/// own, and a refusal asked again on a timer is the same refusal.
final checkInProvider = AsyncNotifierProvider.autoDispose<CheckInNotifier, MyAttendanceDay>(
  CheckInNotifier.new,
  retry: (retryCount, error) => null,
);

/// Checking in and out (docs/staff-check-in.md).
///
/// Where the phone is comes from the device and is sent once with the tap;
/// whether that is close enough is the server's decision. A refusal - too
/// far, too vague, already in - comes back as a [Failure] with the server's
/// own sentence for the card to show.
class CheckInNotifier extends AsyncNotifier<MyAttendanceDay> {
  @override
  Future<MyAttendanceDay> build() => ref.read(checkInRepositoryProvider).today();

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Throws [Failure] when the location cannot be had or the server says no.
  Future<MyAttendanceDay> checkIn() => _act((at) => ref.read(checkInRepositoryProvider).checkIn(at));

  Future<MyAttendanceDay> checkOut() => _act((at) => ref.read(checkInRepositoryProvider).checkOut(at));

  Future<MyAttendanceDay> _act(Future<MyAttendanceDay> Function(DevicePosition at) send) async {
    final position = await _whereAmI();
    final day = await send(position);
    state = AsyncData(day);
    return day;
  }

  Future<DevicePosition> _whereAmI() async {
    final location = ref.read(locationSourceProvider);
    final access = await location.requestAccess();

    if (access != LocationAccess.granted) throw locationFailure(access);

    try {
      return await location.currentPosition();
    } on LocationUnavailable catch (e) {
      throw locationFailure(e.access);
    }
  }
}

/// Why the phone's position could not be had, said so a person can act on it.
Failure locationFailure(LocationAccess access) {
  final message = switch (access) {
    LocationAccess.serviceOff => "Your phone's location is switched off. Turn it on, then check in again.",
    LocationAccess.deniedForever =>
      "This app is not allowed to see your location. Allow it in your phone's settings for this app, "
          'then check in again.',
    LocationAccess.denied =>
      'Checking in needs your location once, to confirm you are at school. Allow it and try again.',
    LocationAccess.unsupported => 'This device cannot tell where it is, so it cannot check you in.',
    LocationAccess.granted => 'Your location could not be found. Try again in a moment.',
  };

  return Failure(code: 'LOCATION_${access.name.toUpperCase()}', message: message);
}
