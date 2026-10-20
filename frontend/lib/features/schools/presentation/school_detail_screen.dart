import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../maps/presentation/app_map.dart';
import '../../maps/presentation/map_pin_icons.dart';
import '../application/school_detail_notifier.dart';
import '../data/models/school.dart';
import 'edit_school_dialog.dart';

/// One school, on a page of its own.
///
/// Opened from the list and from a pin on the schools map. **Read-only**: the
/// map here is for looking at where a school is, and moving the pin belongs
/// on the edit form, where the change is saved. Editing is a button away.
class SchoolDetailScreen extends ConsumerWidget {
  const SchoolDetailScreen({super.key, required this.schoolId});

  final int schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(schoolDetailProvider(schoolId));

    return AsyncValueView<School>(
      value: state,
      onRetry: () => ref.invalidate(schoolDetailProvider(schoolId)),
      data: (context, school) => _Detail(school: school),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.school});

  final School school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        SectionHeader(
          title: school.name,
          actions: [
            FilledButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => EditSchoolDialog(school: school),
              ),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Facts(school: school),
              const SizedBox(height: 16),
              _Where(school: school),
            ],
          ),
        ),
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.appColors.muted);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(
                  label: school.status == SchoolStatus.active ? 'Active' : 'Inactive',
                  tone: school.status == SchoolStatus.active ? BadgeTone.success : BadgeTone.neutral,
                ),
                if (school.parentSchoolName case final parent?)
                  StatusBadge(label: 'Branch of $parent', tone: BadgeTone.info),
                if (school.branchCount > 0)
                  StatusBadge(
                    label: school.branchCount == 1 ? '1 branch' : '${school.branchCount} branches',
                    tone: BadgeTone.info,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final fact in <(String, String?)>[
              ('Registration number', school.registrationNumber),
              ('Email', school.email),
              ('Phone', school.phone),
              ('Address', '${school.address}, ${school.city}, ${school.state} ${school.postalCode}'),
              ('Country', school.country),
              ('Currency', school.currencyCode),
              ('Timezone', school.timezone),
              ('Working days', school.workingDays.summary),
            ])
              if ((fact.$2 ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 170, child: Text(fact.$1, style: muted)),
                      Expanded(child: Text(fact.$2!)),
                    ],
                  ),
                ),
            if (school.workingDays.halfDayNote case final note?)
              Padding(
                padding: const EdgeInsets.only(left: 170),
                child: Text(note, style: muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where the school is, or a plain statement that nobody has said.
class _Where extends ConsumerWidget {
  const _Where({required this.school});

  final School school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = _point(school.latitude, school.longitude);

    if (at == null) {
      // Not an empty frame, and not a pin at (0, 0) off the coast of
      // Africa: the thing somebody needs here is the way to go and place it.
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(Icons.location_off_outlined, color: context.appColors.muted),
              const SizedBox(width: 10),
              const Expanded(child: Text('Nobody has placed this school on the map yet.')),
              TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => EditSchoolDialog(school: school),
                ),
                child: const Text('Place it'),
              ),
            ],
          ),
        ),
      );
    }

    final icons = ref.watch(mapPinIconsProvider).value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AppMap(
          height: 360,
          view: AppMapView(
            centre: at,
            zoom: 15,
            markers: {
              Marker(
                markerId: MarkerId('school-${school.id}'),
                position: at,
                icon: icons?[MapPinColour.primary] ?? BitmapDescriptor.defaultMarker,
                infoWindow: InfoWindow(title: school.name, snippet: school.city),
              ),
            },
          ),
        ),
      ),
    );
  }

  /// Null unless both halves are there and both are on the earth. Each is
  /// nullable on its own, so half a coordinate is reachable however much the
  /// form refuses it.
  static LatLng? _point(String? latitude, String? longitude) {
    final lat = double.tryParse(latitude ?? '');
    final lng = double.tryParse(longitude ?? '');

    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;

    return LatLng(lat, lng);
  }
}
