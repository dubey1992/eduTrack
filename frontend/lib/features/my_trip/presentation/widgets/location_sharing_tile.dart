import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    final String subtitle;
    if (message != null) {
      subtitle = message;
    } else if (sharing.starting) {
      subtitle = 'Asking for your location...';
    } else if (sharing.enabled) {
      subtitle = 'The school can see where the bus is while this screen is open.';
    } else {
      subtitle = 'Off - the school cannot see where the bus is.';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: SwitchListTile(
        key: const Key('share-location-switch'),
        secondary: const Icon(Icons.my_location),
        title: const Text('Share my location'),
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
}
