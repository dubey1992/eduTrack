import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/driver.dart';
import '../data/models/transport_route.dart';
import '../data/models/vehicle.dart';
import '../data/transport_repository.dart';

/// Active vehicles of a school, for the route form. [schoolId] only matters
/// for a SUPER_ADMIN - everyone else is scoped server-side (pass null).
final vehiclePickerProvider = FutureProvider.autoDispose.family<List<Vehicle>, int?>((ref, schoolId) {
  return ref.watch(transportRepositoryProvider).activeVehicles(schoolId: schoolId);
});

final driverPickerProvider = FutureProvider.autoDispose.family<List<Driver>, int?>((ref, schoolId) {
  return ref.watch(transportRepositoryProvider).activeDrivers(schoolId: schoolId);
});

/// Active routes, for the student form's "No Transport / Bus 04 - Green
/// Park" picker.
final routePickerProvider = FutureProvider.autoDispose.family<List<TransportRoute>, int?>((ref, schoolId) {
  return ref.watch(transportRepositoryProvider).activeRoutes(schoolId: schoolId);
});

/// A route's ordered stops, for the student form's stop picker.
final routeStopsProvider = FutureProvider.autoDispose.family<List<TransportStop>, int>((ref, routeId) async {
  final route = await ref.watch(transportRepositoryProvider).getRoute(routeId);
  return route.stops;
});
