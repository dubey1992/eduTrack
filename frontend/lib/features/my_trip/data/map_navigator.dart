import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands the next stop to the maps app the driver already uses.
///
/// Not a map inside this app: drawing one would mean the Navigation SDK, a
/// licence, and asking a driver to learn a second way of doing the thing
/// they do every day (docs/driver-app.md, D5.1). Behind an interface so
/// tests never leave the app.
abstract class MapNavigator {
  /// True when a maps app took it.
  Future<bool> navigateTo({required double latitude, required double longitude});
}

class UrlLauncherMapNavigator implements MapNavigator {
  const UrlLauncherMapNavigator();

  @override
  Future<bool> navigateTo({required double latitude, required double longitude}) async {
    final turnByTurn = navigationUri(latitude, longitude);

    // google.navigation: starts guidance straight away, which is what
    // somebody about to pull out of a stop wants. It only exists where
    // Google Maps is installed, so the web link is the fallback rather
    // than a dead button.
    if (await canLaunchUrl(turnByTurn)) return launchUrl(turnByTurn);

    return launchUrl(directionsUri(latitude, longitude), mode: LaunchMode.externalApplication);
  }
}

/// `google.navigation:q=12.97,77.59&mode=d` - Google Maps' own scheme for
/// "drive me here now".
Uri navigationUri(double latitude, double longitude) => Uri.parse('google.navigation:q=$latitude,$longitude&mode=d');

/// The same destination as an ordinary link, for a phone without Google
/// Maps and for the web build.
Uri directionsUri(double latitude, double longitude) => Uri.https('www.google.com', '/maps/dir/', {
  'api': '1',
  'destination': '$latitude,$longitude',
  'travelmode': 'driving',
});

final mapNavigatorProvider = Provider<MapNavigator>((ref) => const UrlLauncherMapNavigator());
