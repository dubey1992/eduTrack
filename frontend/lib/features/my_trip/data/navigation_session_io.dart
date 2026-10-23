import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import 'navigation_session.dart';

NavigationSession createNavigationSession() => AndroidNavigationSession();

/// Google's Navigation SDK, driving a map inside this app.
///
/// The hand-off to Google Maps (D5.1) still exists and is still the
/// fallback: everything here can refuse - the key may not have the
/// Navigation SDK enabled, the driver may decline Google's terms - and a
/// bus must reach its stop either way.
class AndroidNavigationSession implements NavigationSession {
  /// The company name Google's terms dialog shows the driver. Their terms,
  /// our name on the app they are being shown inside.
  static const _company = 'School365ai';

  /// How long any one call to the SDK is given before the app gives up on
  /// it. Found the hard way: with a key the Navigation SDK is not enabled
  /// for, the SDK logs "Authorization failure" and then simply never
  /// answers - leaving a driver on a spinner with a bus to run. A refusal
  /// the app can see is a fallback; silence has to become one.
  static const _patience = Duration(seconds: 10);

  bool _sessionOpen = false;

  @override
  Future<bool> isSupported() async {
    try {
      // Asked of the terms rather than of the session: a session only
      // exists once guidance has started, so asking about *that* would
      // mean the answer was always no and the in-app route was never
      // taken. This only establishes that the SDK is here and answering;
      // whether the key is allowed to use it is [guideTo]'s discovery.
      await GoogleMapsNavigator.areTermsAccepted();
      return true;
    } on Object catch (error) {
      developer.log('Navigation SDK unavailable', name: 'navigation', error: error);
      return false;
    }
  }

  @override
  Future<NavigationOutcome> guideTo({
    required double latitude,
    required double longitude,
    required String stopName,
  }) async {
    try {
      // Google requires their terms be shown before a session exists, and
      // the SDK remembers the answer - so a driver sees this once, not
      // every morning.
      if (!await GoogleMapsNavigator.areTermsAccepted().timeout(_patience)) {
        // Bounded too, and this one is a judgement call. Google's consent
        // is a short notice with one button, so half a minute is generous
        // for somebody who means to accept it - and it is the only way out
        // of the case that actually happens: with an unauthorised key the
        // dialog never appears *and* never returns, so an unbounded wait
        // here is a driver holding a spinner with a run to start.
        final accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
          'Navigate to your stops',
          _company,
        ).timeout(const Duration(seconds: 30));
        if (!accepted) return NavigationOutcome.termsRefused;
      }

      if (!await GoogleMapsNavigator.isInitialized().timeout(_patience)) {
        await GoogleMapsNavigator.initializeNavigationSession().timeout(_patience);
      }
      _sessionOpen = true;

      final status = await _routeTo(stopName, latitude, longitude).timeout(_patience);

      if (status != NavigationRouteStatus.statusOk) {
        developer.log('No route to the stop', name: 'navigation', error: status.name);

        // An unauthorised key is the one the office can fix, and the most
        // likely one on a build whose Cloud project has Maps enabled but
        // not Navigation. It is not "no route" and must not read like it.
        return status == NavigationRouteStatus.apiKeyNotAuthorized
            ? NavigationOutcome.unavailable
            : NavigationOutcome.noRoute;
      }

      await GoogleMapsNavigator.startGuidance().timeout(_patience);
      return NavigationOutcome.guiding;
    } on Object catch (error) {
      developer.log('Could not start guidance', name: 'navigation', error: error);
      return NavigationOutcome.unavailable;
    }
  }

  Future<NavigationRouteStatus> _routeTo(String stopName, double latitude, double longitude) {
    return GoogleMapsNavigator.setDestinations(
      Destinations(
        waypoints: [
          NavigationWaypoint(
            title: stopName,
            target: LatLng(latitude: latitude, longitude: longitude),
          ),
        ],
        displayOptions: NavigationDisplayOptions(showDestinationMarkers: true),
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (!_sessionOpen) return;
    _sessionOpen = false;

    try {
      await GoogleMapsNavigator.stopGuidance();
      await GoogleMapsNavigator.cleanup();
    } on Object catch (error) {
      // Nothing the crew can do about a session that will not close, and
      // the trip is not held up by it.
      developer.log('Could not close the navigation session', name: 'navigation', error: error);
    }
  }

  @override
  Widget view() => GoogleMapsNavigationView(
    onViewCreated: (_) {},
    initialNavigationUIEnabledPreference: NavigationUIEnabledPreference.automatic,
  );
}
