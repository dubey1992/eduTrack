import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/route_page_notifier.dart';
import '../data/models/transport_route.dart';
import '../data/models/transport_status.dart';
import 'manage_stops_dialog.dart';
import 'route_form_dialog.dart';
import 'route_students_dialog.dart';
import 'widgets/transport_list_scaffold.dart';

/// The fleet stays with administrators: a Transport Manager's manage on the
/// module runs trips, not this list (docs/settings.md).
const _manageRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin};

/// Who may open the "Students on Bus" list - the prototype's "Transport
/// Students" access (admins + the Transport Manager).
const _riderViewerRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.transportManager};

class RouteListScreen extends ConsumerStatefulWidget {
  const RouteListScreen({super.key});

  @override
  ConsumerState<RouteListScreen> createState() => _RouteListScreenState();
}

class _RouteListScreenState extends ConsumerState<RouteListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final routesState = ref.watch(routePageNotifierProvider);
    final actor = ref.watch(authNotifierProvider).value;
    final role = actor?.role;
    final canManage = actor != null && _manageRoles.contains(role) && actor.canManage(AppModules.transport);
    final canViewRiders = _riderViewerRoles.contains(role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Routes',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const RouteFormDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Route'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(routePageNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<TransportRoute>>(
            value: routesState,
            onRetry: () => ref.read(routePageNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No routes defined yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) =>
                          _RouteCards(routes: page.items, canManage: canManage, canViewRiders: canViewRiders),
                      desktop: (context) =>
                          _RouteTable(routes: page.items, canManage: canManage, canViewRiders: canViewRiders),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(routePageNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(routePageNotifierProvider.notifier).setPerPage(p),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

String _occupancy(TransportRoute route) {
  return route.capacity == null ? '${route.studentsCount}' : '${route.studentsCount} / ${route.capacity}';
}

class _OccupancyCell extends StatelessWidget {
  const _OccupancyCell({required this.route});

  final TransportRoute route;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_occupancy(route)),
        if (route.isFull) ...[const SizedBox(width: 8), const StatusBadge(label: 'Full', tone: BadgeTone.warning)],
      ],
    );
  }
}

class _RouteActions extends ConsumerWidget {
  const _RouteActions({required this.route, required this.canManage, required this.canViewRiders});

  final TransportRoute route;
  final bool canManage;
  final bool canViewRiders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(routePageNotifierProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => ManageStopsDialog(routeId: route.id, canManage: canManage),
          ),
          child: const Text('Stops'),
        ),
        if (canViewRiders)
          TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => RouteStudentsDialog(route: route),
            ),
            child: const Text('Students'),
          ),
        if (canManage) ...[
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            onPressed: () => showDialog(
              context: context,
              builder: (_) => RouteFormDialog(route: route),
            ),
          ),
          TextButton(
            onPressed: () => runAndReport(
              context,
              successMessage: '${route.name} is now ${route.isActive ? 'inactive' : 'active'}.',
              action: () => notifier.updateRoute(
                route,
                vehicleId: route.vehicleId,
                driverId: route.driverId,
                attendantUserId: route.attendantUserId,
                status: route.isActive ? TransportStatus.inactive : TransportStatus.active,
              ),
            ),
            child: Text(route.isActive ? 'Deactivate' : 'Activate'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            onPressed: () => confirmAndRun(
              context,
              title: 'Delete route?',
              message: 'This will permanently delete "${route.name}" and its stops. This cannot be undone.',
              successMessage: '${route.name} was deleted.',
              action: () => notifier.deleteRoute(route),
            ),
          ),
        ],
      ],
    );
  }
}

class _RouteTable extends StatelessWidget {
  const _RouteTable({required this.routes, required this.canManage, required this.canViewRiders});

  final List<TransportRoute> routes;
  final bool canManage;
  final bool canViewRiders;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Route')),
              DataColumn(label: Text('Vehicle')),
              DataColumn(label: Text('Driver')),
              DataColumn(label: Text('Attendant')),
              DataColumn(label: Text('Stops')),
              DataColumn(label: Text('Students')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final route in routes)
                DataRow(
                  cells: [
                    DataCell(Text(route.name)),
                    DataCell(Text(route.vehicleName ?? 'No vehicle')),
                    DataCell(Text(route.driverName ?? 'No driver')),
                    DataCell(Text(route.attendantName ?? 'No attendant')),
                    DataCell(Text('${route.stopsCount}')),
                    DataCell(_OccupancyCell(route: route)),
                    DataCell(TransportStatusBadge(status: route.status)),
                    DataCell(_RouteActions(route: route, canManage: canManage, canViewRiders: canViewRiders)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteCards extends StatelessWidget {
  const _RouteCards({required this.routes, required this.canManage, required this.canViewRiders});

  final List<TransportRoute> routes;
  final bool canManage;
  final bool canViewRiders;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: routes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final route = routes[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(route.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    TransportStatusBadge(status: route.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${route.driverName ?? 'No driver'} · ${route.stopsCount} stops · ${_occupancy(route)} students'
                  '${route.isFull ? ' · Full' : ''}',
                  style: muted,
                ),
                Text('Attendant: ${route.attendantName ?? 'None'}', style: muted),
                const SizedBox(height: 4),
                _RouteActions(route: route, canManage: canManage, canViewRiders: canViewRiders),
              ],
            ),
          ),
        );
      },
    );
  }
}
