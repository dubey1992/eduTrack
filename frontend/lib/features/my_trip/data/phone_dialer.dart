import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's dialler with a number ready to call - Call Parent on
/// the My Trip screen. Behind an interface so tests never leave the app.
abstract class PhoneDialer {
  /// True when the dialler opened.
  Future<bool> dial(String number);
}

/// url_launcher is the flutter.dev team's plugin for handing a URL to
/// another app; a `tel:` link is how Android (and a phone's browser) opens
/// the dialler without the app needing the CALL_PHONE permission.
class UrlLauncherPhoneDialer implements PhoneDialer {
  const UrlLauncherPhoneDialer();

  @override
  Future<bool> dial(String number) => launchUrl(telUri(number));
}

/// The `tel:` link for [number]: "+91 98765 43210" -> tel:+919876543210.
/// Spaces and dashes are for people; a dialler wants the digits.
Uri telUri(String number) => Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^\d+]'), ''));

final phoneDialerProvider = Provider<PhoneDialer>((ref) => const UrlLauncherPhoneDialer());
