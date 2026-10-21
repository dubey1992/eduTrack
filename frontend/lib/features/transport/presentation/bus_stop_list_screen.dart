import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/application/auth_notifier.dart';
import '../../maps/presentation/app_map.dart';
import '../../maps/presentation/map_pin_icons.dart';
import '../application/bus_stop_page_notifier.dart';
import '../data/models/bus_stop.dart';
import 'bus_stop_form_dialog.dart';

/// Whoever may define a route may define the places it calls at.
const _manageRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.transportManager};

/// The school's list of bus stops (docs/maps.md).
///
/// The places, not the calls: a route stopping somewhere fourth at 07:15 is
/// Routes & Stops. This is the corner by the post office, kept once and
/// used by every route that passes it.
///
/// A map beside a list, because a stop is a place: the list answers "what
/// do we serve?" and the map answers "where is it?", and neither on its own
/// is enough to spot the pin somebody dropped in the wrong street.
class BusStopListScreen extends ConsumerStatefulWidget {
  const BusStopListScreen({super.key});

  @override
  ConsumerState<BusStopListScreen> createState() => _BusStopListScreenState();
}

class _BusStopListScreenState extends ConsumerState<BusStopListScreen> {
  final _searchController = TextEditingController();
  Timer? _typing;
  int? _schoolFilter;
  int? _selected;

  @override
  void dispose() {
    _typing?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String term) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      ref.read(busStopPageNotifierProvider.notifier).setSearch(term);
    });
  }

  /// Where to centre a map with nothing on it yet, and what a new stop is
  /// measured against.
  ///
  /// Read off the page rather than the schools list: the people who keep
  /// this list cannot read /schools at all - a Transport Manager answers
  /// for their own school without being able to list schools.
  LatLng? _school() {
    final notifier = ref.read(busStopPageNotifierProvider.notifier);
    final latitude = double.tryParse(notifier.schoolLatitude ?? '');
    final longitude = double.tryParse(notifier.schoolLongitude ?? '');

    if (latitude == null || longitude == null) return null;

    return LatLng(latitude, longitude);
  }

  Future<void> _add({LatLng? at}) async {
    await showDialog(
      context: context,
      builder: (_) => BusStopFormDialog(schoolId: _schoolFilter, at: at),
    );
  }

  Future<void> _remove(BusStop stop) async {
    final sure = await confirmDialog(
      context,
      title: 'Remove ${stop.name}?',
      // Said before, not after: the server refuses it anyway, but somebody
      // about to press this should know which answer they will get.
      message: stop.isOnARoute
          ? '${stop.name} is on ${stop.routesCount} route${stop.routesCount == 1 ? '' : 's'}. '
                'Take it off there first, or make it inactive instead.'
          : 'It is on no routes, so nothing else changes.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );

    if (!sure || !mounted) return;

    try {
      await ref.read(busStopPageNotifierProvider.notifier).removeStop(stop);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageOf(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(busStopPageNotifierProvider);
    final notifier = ref.read(busStopPageNotifierProvider.notifier);
    final actor = ref.watch(authNotifierProvider).value;
    final canManage = actor != null && _manageRoles.contains(actor.role) && actor.canManage(AppModules.transport);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Bus Stops',
          actions: [
            if (canManage)
              FilledButton.icon(
                key: const Key('add-bus-stop'),
                onPressed: () => _add(),
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Add Stop'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                notifier.setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search stops',
                    hintText: 'Name or landmark',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                  ),
                  onChanged: _search,
                ),
              ),
              FilterChip(
                key: const Key('active-only'),
                label: const Text('Active only'),
                selected: notifier.status == 'active',
                onSelected: (only) => notifier.setStatus(only ? 'active' : null),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncValueView<PagedList<BusStop>>(
            value: state,
            onRetry: notifier.refresh,
            data: (context, page) => _MapAndList(
              stops: page.items,
              page: page,
              canManage: canManage,
              school: _school(),
              selected: _selected,
              onSelect: (id) => setState(() => _selected = id),
              onAddAt: canManage ? (at) => _add(at: at) : null,
              onEdit: (stop) => showDialog(
                context: context,
                builder: (_) => BusStopFormDialog(stop: stop),
              ),
              onRemove: _remove,
              onPageChanged: notifier.goToPage,
              onPerPageChanged: notifier.setPerPage,
            ),
          ),
        ),
      ],
    );
  }
}

/// A failure's own sentence, or a last-resort one.
String messageOf(Object error) {
  final message = (error as dynamic);

  try {
    return message.message as String;
  } catch (_) {
    return 'Something went wrong. Please try again.';
  }
}

class _MapAndList extends ConsumerWidget {
  const _MapAndList({
    required this.stops,
    required this.page,
    required this.canManage,
    required this.school,
    required this.selected,
    required this.onSelect,
    required this.onAddAt,
    required this.onEdit,
    required this.onRemove,
    required this.onPageChanged,
    required this.onPerPageChanged,
  });

  final List<BusStop> stops;
  final PagedList<BusStop> page;
  final bool canManage;
  final LatLng? school;
  final int? selected;
  final void Function(int id) onSelect;
  final void Function(LatLng at)? onAddAt;
  final void Function(BusStop stop) onEdit;
  final void Function(BusStop stop) onRemove;
  final void Function(int page) onPageChanged;
  final void Function(int perPage) onPerPageChanged;

  LatLng? _at(BusStop stop) {
    final latitude = double.tryParse(stop.latitude);
    final longitude = double.tryParse(stop.longitude);

    if (latitude == null || longitude == null) return null;

    return LatLng(latitude, longitude);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = ref.watch(mapPinIconsProvider).value;
    final places = [
      for (final stop in stops)
        if (_at(stop) != null) _at(stop)!,
    ];
    // The first stop, not an average: a list is read in name order, so
    // opening on the first one is a place somebody can relate to the list
    // beside it.
    final centre = places.isEmpty ? school : places.first;
    final isWide = MediaQuery.sizeOf(context).width >= 1000;

    final map = centre == null
        ? const _NoSchoolYet()
        : AppMap(
            height: isWide ? null : 320,
            view: AppMapView(
              centre: centre,
              zoom: places.isEmpty ? 14 : 13,
              onTap: onAddAt,
              markers: {
                for (final stop in stops)
                  if (_at(stop) != null)
                    Marker(
                      markerId: MarkerId('bus-stop-${stop.id}'),
                      position: _at(stop)!,
                      icon:
                          icons?[stop.id == selected
                              ? MapPinColour.muted
                              : stop.isActive
                              ? MapPinColour.secondary
                              : MapPinColour.done] ??
                          BitmapDescriptor.defaultMarker,
                      infoWindow: InfoWindow(title: stop.name, snippet: stop.landmark),
                      onTap: () => onSelect(stop.id),
                    ),
              },
            ),
          );

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canManage && centre != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Tap the map to add a stop where you tap.', style: TextStyle(color: context.appColors.muted)),
          ),
        Expanded(
          child: stops.isEmpty
              ? const Center(child: Text('No bus stops yet.'))
              : ListView.separated(
                  itemCount: stops.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _StopRow(
                    stop: stops[index],
                    selected: stops[index].id == selected,
                    canManage: canManage,
                    onTap: () => onSelect(stops[index].id),
                    onEdit: () => onEdit(stops[index]),
                    onRemove: () => onRemove(stops[index]),
                  ),
                ),
        ),
        PaginationControls(
          currentPage: page.currentPage,
          lastPage: page.lastPage,
          total: page.total,
          perPage: page.perPage,
          onPageChanged: onPageChanged,
          onPerPageChanged: onPerPageChanged,
        ),
      ],
    );

    if (!isWide) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          map,
          const SizedBox(height: 16),
          SizedBox(height: 420, child: list),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: map),
          const SizedBox(width: 16),
          SizedBox(width: 420, child: list),
        ],
      ),
    );
  }
}

class _NoSchoolYet extends StatelessWidget {
  const _NoSchoolYet();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.location_off_outlined, color: context.appColors.muted),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Place the school on the map first - a stop is measured against where the school is.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.selected,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  final BusStop stop;
  final bool selected;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final notes = [
      if (stop.landmark != null && stop.landmark!.isNotEmpty) stop.landmark!,
      // Said on every row, because it is what decides whether a stop can be
      // removed and how much a move is about to change.
      stop.routesCount == 0 ? 'On no routes' : 'On ${stop.routesCount} route${stop.routesCount == 1 ? '' : 's'}',
    ].join(' · ');

    return ListTile(
      selected: selected,
      onTap: onTap,
      title: Row(
        children: [
          Flexible(child: Text(stop.name, overflow: TextOverflow.ellipsis)),
          if (!stop.isActive) ...[
            const SizedBox(width: 8),
            Chip(
              label: const Text('Inactive'),
              labelStyle: TextStyle(fontSize: 11, color: colors.muted),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: colors.muted),
              backgroundColor: Colors.transparent,
            ),
          ],
        ],
      ),
      subtitle: Text(notes, style: TextStyle(color: colors.muted)),
      trailing: canManage
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit_outlined, size: 18), tooltip: 'Edit', onPressed: onEdit),
                IconButton(icon: const Icon(Icons.delete_outline, size: 18), tooltip: 'Remove', onPressed: onRemove),
              ],
            )
          : null,
    );
  }
}
