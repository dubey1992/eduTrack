import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/module_access.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../staff/data/models/staff_profile.dart';
import '../../staff/presentation/attendant_sign_in_dialog.dart';
import '../../staff/presentation/edit_staff_profile_dialog.dart';
import '../../users/data/models/app_user.dart';
import '../application/crew_list_notifier.dart';
import '../application/driver_page_notifier.dart';
import '../data/models/driver.dart';
import 'crew_form_dialog.dart';
import 'driver_form_dialog.dart';
import 'widgets/transport_list_scaffold.dart';

/// The people on the bus (docs/driver-app.md, D10).
///
/// Drivers and attendants are employees who sign in to the Driver app, so
/// this is a view of the staff list narrowed to the two crew roles - with
/// the licence a driver carries, and the Sign-in panel that hands out setup
/// codes. Whoever manages transport may add and look after them, which is
/// the Transport Manager's whole reach into the staff of the school; the
/// School Admin reaches the same people from Teachers & Staff.
class CrewListScreen extends ConsumerStatefulWidget {
  const CrewListScreen({super.key});

  @override
  ConsumerState<CrewListScreen> createState() => _CrewListScreenState();
}

class _CrewListScreenState extends ConsumerState<CrewListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final crewState = ref.watch(crewListNotifierProvider);
    final actor = ref.watch(authNotifierProvider).value;
    final canManage =
        actor != null &&
        !actor.role.isCrew &&
        (actor.canManage(AppModules.staff) || actor.canManage(AppModules.transport));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Bus crew',
          actions: [
            if (canManage)
              FilledButton.icon(
                key: const Key('add-crew'),
                onPressed: () => showDialog(context: context, builder: (_) => const CrewFormDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add crew'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(crewListNotifierProvider.notifier).setSchoolFilter(schoolId);
                ref.read(driverPageNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<StaffProfile>>(
            value: crewState,
            onRetry: () => ref.read(crewListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No drivers or attendants yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _CrewCards(crew: page.items, canManage: canManage),
                      desktop: (context) => _CrewTable(crew: page.items, canManage: canManage),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(crewListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(crewListNotifierProvider.notifier).setPerPage(p),
                  ),
                ],
              );
            },
          ),
        ),
        _UnlinkedDrivers(canManage: canManage),
      ],
    );
  }
}

String _licenceLabel(StaffProfile member) {
  final number = member.licenceNumber;
  if (number == null) return '-';
  if (member.licenceExpiry == null) return number;
  return '$number · exp. ${formatDate(DateTime.parse(member.licenceExpiry!))}';
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.member});

  final StaffProfile member;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: member.isDriver ? 'Driver' : 'Attendant',
      tone: member.isDriver ? BadgeTone.info : BadgeTone.neutral,
    );
  }
}

class _LicenceBadge extends ConsumerWidget {
  const _LicenceBadge({required this.member});

  final StaffProfile member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiry = member.licenceExpiry;
    if (expiry == null) return const SizedBox.shrink();
    final today = ref.watch(schoolClockProvider).today;
    if (!DateTime.parse(expiry).isBefore(DateTime(today.year, today.month, today.day))) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.only(left: 8),
      child: StatusBadge(label: 'Licence expired', tone: BadgeTone.danger),
    );
  }
}

class _CrewActions extends ConsumerWidget {
  const _CrewActions({required this.member});

  final StaffProfile member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(crewListNotifierProvider.notifier);
    final active = member.status == UserStatus.active;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('crew-edit-${member.id}'),
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: 'Edit',
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            await showDialog<void>(
              context: context,
              builder: (_) => EditStaffProfileDialog(profile: member),
            );
            // The edit dialog writes through the Teachers & Staff notifier;
            // this list has its own page to bring up to date.
            await notifier.refresh();
          },
        ),
        IconButton(
          key: Key('crew-sign-in-${member.id}'),
          icon: const Icon(Icons.phonelink_lock_outlined, size: 18),
          tooltip: 'Sign-in & phones',
          visualDensity: VisualDensity.compact,
          onPressed: () => showDialog(
            context: context,
            builder: (_) => AttendantSignInDialog(profile: member),
          ),
        ),
        TextButton(
          key: Key('crew-active-${member.id}'),
          onPressed: () => runAndReport(
            context,
            successMessage: '${member.name} is now ${active ? 'inactive' : 'active'}.',
            action: () => notifier.setActive(member, !active),
          ),
          child: Text(active ? 'Deactivate' : 'Activate'),
        ),
      ],
    );
  }
}

class _CrewTable extends StatelessWidget {
  const _CrewTable({required this.crew, required this.canManage});

  final List<StaffProfile> crew;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Name')),
              const DataColumn(label: Text('Role')),
              const DataColumn(label: Text('Mobile')),
              const DataColumn(label: Text('Licence')),
              const DataColumn(label: Text('Status')),
              if (canManage) const DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final member in crew)
                DataRow(
                  key: ValueKey('crew-row-${member.id}'),
                  cells: [
                    DataCell(Text(member.name)),
                    DataCell(_RoleBadge(member: member)),
                    DataCell(Text(member.mobile ?? '-')),
                    DataCell(
                      Row(
                        children: [
                          Text(_licenceLabel(member)),
                          _LicenceBadge(member: member),
                        ],
                      ),
                    ),
                    DataCell(
                      StatusBadge(
                        label: member.status == UserStatus.active ? 'Active' : 'Inactive',
                        tone: member.status == UserStatus.active ? BadgeTone.success : BadgeTone.neutral,
                      ),
                    ),
                    if (canManage) DataCell(_CrewActions(member: member)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrewCards extends StatelessWidget {
  const _CrewCards({required this.crew, required this.canManage});

  final List<StaffProfile> crew;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: crew.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final member = crew[index];
        return Card(
          key: ValueKey('crew-row-${member.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(member.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    _RoleBadge(member: member),
                    _LicenceBadge(member: member),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${member.mobile ?? 'No mobile'}${member.isDriver ? ' · ${_licenceLabel(member)}' : ''}',
                  style: muted,
                ),
                if (canManage) ...[const SizedBox(height: 4), _CrewActions(member: member)],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Driver records from before drivers could sign in - a name and a licence
/// with no employee behind them (docs/driver-app.md, D3). Shown only while
/// any exist, so the office can link each to a member of staff or let the
/// record stand as it is; a new driver is never created this way.
class _UnlinkedDrivers extends ConsumerWidget {
  const _UnlinkedDrivers({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivers = ref.watch(driverPageNotifierProvider).value?.items.where((d) => !d.canSignIn).toList() ?? const [];
    if (drivers.isEmpty) return const SizedBox.shrink();

    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Padding(
      key: const Key('unlinked-drivers'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Driver records without a login (${drivers.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('Kept from before drivers could sign in. Edit one to link it to a member of staff.', style: muted),
              const SizedBox(height: 6),
              for (final Driver driver in drivers)
                Row(
                  children: [
                    Expanded(child: Text('${driver.name} · ${driver.licenceNumber}')),
                    if (canManage)
                      TextButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => DriverFormDialog(driver: driver),
                        ),
                        child: const Text('Edit'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
