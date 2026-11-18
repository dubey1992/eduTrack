import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transport/data/models/transport_trip.dart';
import 'trip_mark_queue.dart';
import '../data/offline_start.dart';
import '../data/models/my_route.dart';
import '../data/my_trip_repository.dart';

final myRoutesProvider = AsyncNotifierProvider.autoDispose<MyRoutesNotifier, MyRoutesDay>(MyRoutesNotifier.new);

/// The routes this attendant runs and today's trips on them - My Trip's
/// opening page.
class MyRoutesNotifier extends AsyncNotifier<MyRoutesDay> {
  @override
  Future<MyRoutesDay> build() => ref.read(myTripRepositoryProvider).myRoutes();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Starts today's [direction] trip on [routeId]. Needs a connection: the
  /// server is what makes the rider list. Throws the server's refusal (not a
  /// working day, already run) as a Failure for the screen to show.
  Future<TransportTrip> start({required int routeId, required TripDirection direction}) async {
    final trip = await ref.read(myTripRepositoryProvider).startTrip(routeId: routeId, direction: direction);
    // Started on the phone (2.4): the queue starts it on the server as soon
    // as there is signal.
    if (isLocalTrip(trip.id)) unawaited(ref.read(tripMarkQueueProvider.notifier).flush());

    // The list learns about the new trip quietly, without a spinner.
    state = await AsyncValue.guard(build);
    return trip;
  }
}
