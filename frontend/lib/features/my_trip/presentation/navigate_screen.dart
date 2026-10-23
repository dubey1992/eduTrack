import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/map_navigator.dart';
import '../data/navigation_session.dart';

/// Where the app is asked to take the bus, so a route can carry it.
class NavigateTo {
  const NavigateTo({required this.latitude, required this.longitude, required this.stopName});

  final double latitude;
  final double longitude;
  final String stopName;
}

/// Turn-by-turn guidance to the next stop, inside this app
/// (docs/driver-app.md, D7).
///
/// Everything about this screen is built around it being allowed to fail.
/// The Navigation SDK needs a key the school's Google Cloud project has
/// switched it on for, and Google's own terms accepted by the driver;
/// either can say no, on a morning, in a yard. When they do, the stop is
/// handed to Google Maps exactly as it was before any of this existed, and
/// the driver is told in one sentence - never left on a blank map.
class NavigateScreen extends ConsumerStatefulWidget {
  const NavigateScreen({super.key, required this.destination});

  final NavigateTo destination;

  @override
  ConsumerState<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends ConsumerState<NavigateScreen> {
  NavigationOutcome? _outcome;

  /// Held from initState rather than read in dispose: a provider cannot be
  /// read from a widget that is being taken down, and closing the session
  /// is exactly what has to happen then.
  late final NavigationSession _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(navigationSessionProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    unawaited(_session.stop());
    super.dispose();
  }

  Future<void> _start() async {
    final destination = widget.destination;
    final outcome = await _session.guideTo(
      latitude: destination.latitude,
      longitude: destination.longitude,
      stopName: destination.stopName,
    );

    if (!mounted) return;
    setState(() => _outcome = outcome);
  }

  /// The road that was always there: hand the stop to Google Maps.
  Future<void> _handOff() async {
    final destination = widget.destination;
    final opened = await ref
        .read(mapNavigatorProvider)
        .navigateTo(latitude: destination.latitude, longitude: destination.longitude);

    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not open a maps app on this phone.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;

    return Scaffold(
      appBar: AppBar(title: Text(widget.destination.stopName)),
      body: switch (outcome) {
        null => const Center(child: CircularProgressIndicator()),
        NavigationOutcome.guiding => _session.view(),
        NavigationOutcome.termsRefused => _Fallback(
          key: const Key('nav-terms-refused'),
          message:
              'Guidance inside this app needs Google\'s terms, which you did not accept. '
              'You can still use Google Maps.',
          onHandOff: _handOff,
        ),
        NavigationOutcome.noRoute => _Fallback(
          key: const Key('nav-no-route'),
          message: 'No route to this stop could be worked out. Check your signal, or try Google Maps.',
          onHandOff: _handOff,
        ),
        NavigationOutcome.unavailable => _Fallback(
          key: const Key('nav-unavailable'),
          message:
              'Guidance inside this app is not switched on for your school yet. '
              'Google Maps will take you there.',
          onHandOff: _handOff,
        ),
      },
    );
  }
}

/// Said once, with the way onward under it. A driver reads this with the
/// engine running, so it is one sentence and one button.
class _Fallback extends StatelessWidget {
  const _Fallback({super.key, required this.message, required this.onHandOff});

  final String message;
  final VoidCallback onHandOff;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.alt_route, size: 40, color: context.appColors.muted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const Key('nav-hand-off'),
                onPressed: onHandOff,
                icon: const Icon(Icons.directions),
                label: const Text('Open Google Maps'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
