import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../transport/application/transport_pickers.dart';
import '../../../transport/data/models/transport_route.dart';

/// The prototype's "No Transport / Bus 04 - Green Park" pick on the
/// student form, followed by that route's stop once a route is chosen.
/// Reports `(routeId, stopId)`; both null means no transport.
class StudentTransportPicker extends ConsumerWidget {
  const StudentTransportPicker({
    super.key,
    required this.schoolId,
    required this.routeId,
    required this.stopId,
    required this.currentRouteLabel,
    required this.onChanged,
  });

  /// Only a SUPER_ADMIN passes a school; everyone else is scoped server-side.
  final int? schoolId;
  final int? routeId;
  final int? stopId;

  /// Label of the student's existing route, so it stays visible even if
  /// that route has since been deactivated (and dropped out of the picker).
  final String? currentRouteLabel;
  final void Function(int? routeId, int? stopId) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesState = ref.watch(routePickerProvider(schoolId));
    final routes = routesState.value ?? const <TransportRoute>[];
    final routeOptions = <int, String>{for (final route in routes) route.id: route.label};
    if (routeId != null && !routeOptions.containsKey(routeId)) {
      // Until the routes arrive we can't tell whether it's inactive or just
      // not loaded yet - only say so once the list is known.
      final suffix = routesState.hasValue ? ' (inactive)' : '';
      routeOptions[routeId!] = '${currentRouteLabel ?? 'Route #$routeId'}$suffix';
    }

    return Column(
      children: [
        // Disabled while loading: a menu opened before the routes arrive
        // would only ever show "No Transport".
        DropdownButtonFormField<int?>(
          key: ValueKey('route-$routeId-${routes.length}'),
          initialValue: routeId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Transport',
            helperText: routesState.isLoading ? 'Loading routes…' : null,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('No Transport')),
            for (final entry in routeOptions.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: routesState.isLoading ? null : (value) => onChanged(value, null),
        ),
        if (routeId != null) ...[
          const SizedBox(height: 10),
          _StopPicker(routeId: routeId!, selected: stopId, onChanged: (value) => onChanged(routeId, value)),
        ],
      ],
    );
  }
}

class _StopPicker extends ConsumerWidget {
  const _StopPicker({required this.routeId, required this.selected, required this.onChanged});

  final int routeId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stopsState = ref.watch(routeStopsProvider(routeId));
    final stops = stopsState.value ?? const <TransportStop>[];

    final helper = stopsState.isLoading
        ? 'Loading stops…'
        : (stopsState.hasValue && stops.isEmpty ? 'This route has no stops yet - add stops first.' : null);

    return DropdownButtonFormField<int>(
      key: ValueKey('stops-$routeId-${stops.length}'),
      initialValue: stops.any((s) => s.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: 'Stop', helperText: helper),
      items: [
        for (final stop in stops) DropdownMenuItem(value: stop.id, child: Text('${stop.sequenceNumber}. ${stop.name}')),
      ],
      onChanged: stopsState.isLoading ? null : onChanged,
      validator: (v) => v == null ? 'Pick a stop for this route' : null,
    );
  }
}
