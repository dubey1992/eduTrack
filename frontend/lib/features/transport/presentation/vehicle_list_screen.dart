import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/application/auth_notifier.dart';
import '../../imports/presentation/bulk_import_button.dart';
import '../application/vehicle_page_notifier.dart';
import '../data/models/transport_status.dart';
import '../data/models/vehicle.dart';
import 'vehicle_form_dialog.dart';
import 'widgets/transport_list_scaffold.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.schoolAdmin};

class VehicleListScreen extends ConsumerStatefulWidget {
  const VehicleListScreen({super.key});

  @override
  ConsumerState<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends ConsumerState<VehicleListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final vehiclesState = ref.watch(vehiclePageNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Vehicles',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const VehicleFormDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Vehicle'),
              ),
            if (canManage)
              BulkImportButton(
                type: 'vehicles',
                title: 'Vehicles',
                schoolId: _schoolFilter,
                onImported: () => ref.read(vehiclePageNotifierProvider.notifier).refresh(),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(vehiclePageNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<Vehicle>>(
            value: vehiclesState,
            onRetry: () => ref.read(vehiclePageNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No vehicles added yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _VehicleCards(vehicles: page.items, canManage: canManage),
                      desktop: (context) => _VehicleTable(vehicles: page.items, canManage: canManage),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(vehiclePageNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(vehiclePageNotifierProvider.notifier).setPerPage(p),
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

class _VehicleActions extends ConsumerWidget {
  const _VehicleActions({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(vehiclePageNotifierProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: 'Edit',
          visualDensity: VisualDensity.compact,
          onPressed: () => showDialog(
            context: context,
            builder: (_) => VehicleFormDialog(vehicle: vehicle),
          ),
        ),
        TextButton(
          onPressed: () => runAndReport(
            context,
            successMessage: '${vehicle.name} is now ${vehicle.isActive ? 'inactive' : 'active'}.',
            action: () => notifier.updateVehicle(
              vehicle,
              status: vehicle.isActive ? TransportStatus.inactive : TransportStatus.active,
            ),
          ),
          child: Text(vehicle.isActive ? 'Deactivate' : 'Activate'),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: 'Delete',
          visualDensity: VisualDensity.compact,
          onPressed: () => confirmAndRun(
            context,
            title: 'Delete vehicle?',
            message: 'This will permanently delete "${vehicle.name}". This cannot be undone.',
            successMessage: '${vehicle.name} was deleted.',
            action: () => notifier.deleteVehicle(vehicle),
          ),
        ),
      ],
    );
  }
}

class _VehicleTable extends StatelessWidget {
  const _VehicleTable({required this.vehicles, required this.canManage});

  final List<Vehicle> vehicles;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Vehicle')),
              const DataColumn(label: Text('Registration')),
              const DataColumn(label: Text('Capacity')),
              const DataColumn(label: Text('Route')),
              const DataColumn(label: Text('Status')),
              if (canManage) const DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final vehicle in vehicles)
                DataRow(
                  cells: [
                    DataCell(Text(vehicle.name)),
                    DataCell(Text(vehicle.registrationNumber)),
                    DataCell(Text('${vehicle.capacity} seats')),
                    DataCell(Text(vehicle.routeName ?? 'Unassigned')),
                    DataCell(TransportStatusBadge(status: vehicle.status)),
                    if (canManage) DataCell(_VehicleActions(vehicle: vehicle)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleCards extends StatelessWidget {
  const _VehicleCards({required this.vehicles, required this.canManage});

  final List<Vehicle> vehicles;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: vehicles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final vehicle = vehicles[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(vehicle.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    TransportStatusBadge(status: vehicle.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${vehicle.registrationNumber} · ${vehicle.capacity} seats · ${vehicle.routeName ?? 'Unassigned'}',
                  style: muted,
                ),
                if (canManage) ...[const SizedBox(height: 4), _VehicleActions(vehicle: vehicle)],
              ],
            ),
          ),
        );
      },
    );
  }
}
