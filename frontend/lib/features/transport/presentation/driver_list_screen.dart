import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/school_clock_provider.dart';

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
import '../../imports/presentation/bulk_import_button.dart';
import '../application/driver_page_notifier.dart';
import '../data/models/driver.dart';
import '../data/models/transport_status.dart';
import 'driver_form_dialog.dart';
import 'widgets/transport_list_scaffold.dart';
import '../../../core/utils/date_format.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.schoolAdmin};

class DriverListScreen extends ConsumerStatefulWidget {
  const DriverListScreen({super.key});

  @override
  ConsumerState<DriverListScreen> createState() => _DriverListScreenState();
}

class _DriverListScreenState extends ConsumerState<DriverListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final driversState = ref.watch(driverPageNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Drivers',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const DriverFormDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Driver'),
              ),
            if (canManage)
              BulkImportButton(
                type: 'drivers',
                title: 'Drivers',
                schoolId: _schoolFilter,
                onImported: () => ref.read(driverPageNotifierProvider.notifier).refresh(),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(driverPageNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<Driver>>(
            value: driversState,
            onRetry: () => ref.read(driverPageNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No drivers added yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _DriverCards(drivers: page.items, canManage: canManage),
                      desktop: (context) => _DriverTable(drivers: page.items, canManage: canManage),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(driverPageNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(driverPageNotifierProvider.notifier).setPerPage(p),
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

String _licenceLabel(Driver driver) {
  if (driver.licenceExpiry == null) return driver.licenceNumber;
  return '${driver.licenceNumber} · exp. ${formatDate(DateTime.parse(driver.licenceExpiry!))}';
}

class _LicenceBadge extends ConsumerWidget {
  const _LicenceBadge({required this.driver});

  final Driver driver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!driver.isLicenceExpiredOn(ref.watch(schoolClockProvider).today)) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(left: 8),
      child: StatusBadge(label: 'Licence expired', tone: BadgeTone.danger),
    );
  }
}

class _DriverActions extends ConsumerWidget {
  const _DriverActions({required this.driver});

  final Driver driver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(driverPageNotifierProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: 'Edit',
          visualDensity: VisualDensity.compact,
          onPressed: () => showDialog(
            context: context,
            builder: (_) => DriverFormDialog(driver: driver),
          ),
        ),
        TextButton(
          onPressed: () => runAndReport(
            context,
            successMessage: '${driver.name} is now ${driver.isActive ? 'inactive' : 'active'}.',
            action: () => notifier.updateDriver(
              driver,
              status: driver.isActive ? TransportStatus.inactive : TransportStatus.active,
            ),
          ),
          child: Text(driver.isActive ? 'Deactivate' : 'Activate'),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: 'Delete',
          visualDensity: VisualDensity.compact,
          onPressed: () => confirmAndRun(
            context,
            title: 'Delete driver?',
            message: 'This will permanently delete "${driver.name}". This cannot be undone.',
            successMessage: '${driver.name} was deleted.',
            action: () => notifier.deleteDriver(driver),
          ),
        ),
      ],
    );
  }
}

class _DriverTable extends StatelessWidget {
  const _DriverTable({required this.drivers, required this.canManage});

  final List<Driver> drivers;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Driver')),
              const DataColumn(label: Text('Mobile')),
              const DataColumn(label: Text('Licence')),
              const DataColumn(label: Text('Route')),
              const DataColumn(label: Text('Status')),
              if (canManage) const DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final driver in drivers)
                DataRow(
                  cells: [
                    DataCell(Text(driver.name)),
                    DataCell(Text(driver.mobile ?? '-')),
                    DataCell(
                      Row(
                        children: [
                          Text(_licenceLabel(driver)),
                          _LicenceBadge(driver: driver),
                        ],
                      ),
                    ),
                    DataCell(Text(driver.routeName ?? 'Unassigned')),
                    DataCell(TransportStatusBadge(status: driver.status)),
                    if (canManage) DataCell(_DriverActions(driver: driver)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverCards extends StatelessWidget {
  const _DriverCards({required this.drivers, required this.canManage});

  final List<Driver> drivers;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: drivers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final driver = drivers[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(driver.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    _LicenceBadge(driver: driver),
                    const SizedBox(width: 8),
                    TransportStatusBadge(status: driver.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${driver.mobile ?? 'No mobile'} · ${_licenceLabel(driver)}', style: muted),
                Text(driver.routeName ?? 'Unassigned', style: muted),
                if (canManage) ...[const SizedBox(height: 4), _DriverActions(driver: driver)],
              ],
            ),
          ),
        );
      },
    );
  }
}
