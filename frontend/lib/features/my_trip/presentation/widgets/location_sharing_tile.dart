import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/location_sharing_notifier.dart';

/// "Share my location" on a running trip. Watching it is what keeps sharing
/// going: once this tile leaves the screen, so does the sharing.
class LocationSharingTile extends ConsumerWidget {
  const LocationSharingTile({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharing = ref.watch(locationSharingProvider(tripId));
    final message = sharing.message;
    final l10n = context.l10n;

    final String subtitle;
    if (message != null) {
      subtitle = _translated(l10n, message);
    } else if (sharing.starting) {
      subtitle = l10n.busLocAsking;
    } else if (sharing.enabled) {
      subtitle = l10n.busLocOn;
    } else {
      subtitle = l10n.busLocOff;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: SwitchListTile(
        key: const Key('share-location-switch'),
        secondary: const Icon(Icons.my_location),
        title: Text(l10n.busShareLocation),
        subtitle: Text(
          subtitle,
          style: message == null ? null : TextStyle(color: context.appColors.danger, fontWeight: FontWeight.w600),
        ),
        value: sharing.enabled || sharing.starting,
        onChanged: sharing.starting
            ? null
            : (value) => ref.read(locationSharingProvider(tripId).notifier).setEnabled(value),
      ),
    );
  }

  /// The notifier's own reasons in the person's language; anything else
  /// (a server's words) as it came.
  String _translated(AppLocalizations l10n, String message) => switch (message) {
    LocationSharingNotifier.deniedMessage => l10n.busLocDenied,
    LocationSharingNotifier.blockedMessage => l10n.busLocBlocked,
    LocationSharingNotifier.serviceOffMessage => l10n.busLocServiceOff,
    LocationSharingNotifier.unsupportedMessage => l10n.busLocUnsupported,
    LocationSharingNotifier.tripEndedMessage => l10n.busLocTripEnded,
    _ => message,
  };
}
