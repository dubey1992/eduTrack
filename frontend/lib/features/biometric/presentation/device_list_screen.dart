import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/module_access.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/device_page_notifier.dart';
import '../data/models/biometric_device.dart';
import 'device_form_dialog.dart';
import 'punch_upload_dialog.dart';
import 'punch_log_view.dart';
import '../application/punch_page_notifier.dart';
import '../../../core/utils/file_picker.dart';

/// The fingerprint readers a school has (docs/biometric.md, B1).
///
/// A registry: what hardware exists, where it is, and whether it has ever
/// spoken. No punch is read until B2, and the screen says so rather than
/// leaving somebody to wonder why a registered device changes nothing.
class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  int? _schoolFilter;

  /// Two views of the same subject: the hardware, and what it recorded.
  /// One nav entry, because a log without the devices behind it is not a
  /// screen anybody opens on its own.
  bool _onTheLog = false;
  final _searchController = TextEditingController();
  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String term) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      ref.read(devicePageNotifierProvider.notifier).setSearch(term);
    });
  }

  @override
  Widget build(BuildContext context) {
    final devicesState = ref.watch(devicePageNotifierProvider);
    final actor = ref.watch(authNotifierProvider).value;
    final canManage = actor?.canManage(AppModules.staffAttendance) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Biometric Devices',
          actions: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.fingerprint, size: 18), label: Text('Devices')),
                ButtonSegment(value: true, icon: Icon(Icons.list_alt, size: 18), label: Text('Punch log')),
              ],
              selected: {_onTheLog},
              onSelectionChanged: (choice) => setState(() => _onTheLog = choice.first),
            ),
            if (canManage && _onTheLog && canPickFile)
              OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PunchUploadDialog(schoolId: _schoolFilter),
                ),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload punches'),
              ),
            if (canManage && !_onTheLog)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const DeviceFormDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Register Device'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(devicePageNotifierProvider.notifier).setSchoolFilter(schoolId);
                ref.read(punchPageNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        if (_onTheLog)
          const Expanded(child: PunchLogView())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SizedBox(
              width: 340,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search devices',
                  hintText: 'Name, serial number or location',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
                onChanged: _search,
              ),
            ),
          ),
          Expanded(
            child: AsyncValueView<PagedList<BiometricDevice>>(
              value: devicesState,
              onRetry: () => ref.read(devicePageNotifierProvider.notifier).refresh(),
              isEmpty: (page) => page.items.isEmpty,
              emptyBuilder: (context) => const Center(child: Text('No devices registered yet.')),
              data: (context, page) {
                return Column(
                  children: [
                    Expanded(
                      child: ResponsiveBuilder(
                        mobile: (context) => _DeviceCards(devices: page.items, canManage: canManage),
                        desktop: (context) => _DeviceTable(devices: page.items, canManage: canManage),
                      ),
                    ),
                    PaginationControls(
                      currentPage: page.currentPage,
                      lastPage: page.lastPage,
                      total: page.total,
                      perPage: page.perPage,
                      onPageChanged: (p) => ref.read(devicePageNotifierProvider.notifier).goToPage(p),
                      onPerPageChanged: (p) => ref.read(devicePageNotifierProvider.notifier).setPerPage(p),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// "Never heard from", or when it last spoke.
///
/// The two are different things and the screen says which: a device
/// registered this morning and silent is somebody's next job, while one
/// that stopped on Tuesday is a fault.
Widget lastSeen(BuildContext context, BiometricDevice device) {
  final colors = context.appColors;

  if (device.hasNeverSpoken) {
    return Text('Never heard from', style: TextStyle(color: colors.warning));
  }

  return Text(formatDateTime(DateTime.parse(device.lastSeenAt!).toLocal()));
}

class _DeviceTable extends StatelessWidget {
  const _DeviceTable({required this.devices, required this.canManage});

  final List<BiometricDevice> devices;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return HorizontalScrollTable(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Device')),
          DataColumn(label: Text('Serial number')),
          DataColumn(label: Text('Location')),
          DataColumn(label: Text('School')),
          DataColumn(label: Text('Last heard from')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final device in devices)
            DataRow(
              cells: [
                DataCell(_DeviceName(device: device)),
                DataCell(Text(device.serialNumber)),
                DataCell(Text(device.location ?? '-')),
                DataCell(Text(device.schoolName)),
                DataCell(lastSeen(context, device)),
                DataCell(canManage ? _DeviceActions(device: device) : const SizedBox.shrink()),
              ],
            ),
        ],
      ),
    );
  }
}

/// The device's name, and a warning beside it when it has no push key:
/// such a reader takes punches from anybody who knows its serial number
/// (docs/security.md, "The 2026-10-26 review").
class _DeviceName extends StatelessWidget {
  const _DeviceName({required this.device, this.style});

  final BiometricDevice device;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(device.name, style: style),
        if (!device.hasPushKey)
          Tooltip(
            message: 'Anybody who knows the serial number can send punches. Edit the device to set a key.',
            child: StatusBadge(key: Key('no-push-key-${device.id}'), label: 'No key', tone: BadgeTone.warning),
          ),
      ],
    );
  }
}

class _DeviceCards extends StatelessWidget {
  const _DeviceCards({required this.devices, required this.canManage});

  final List<BiometricDevice> devices;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final device = devices[index];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DeviceName(device: device, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(device.serialNumber),
                if (device.location case final where?) Text(where),
                const SizedBox(height: 6),
                lastSeen(context, device),
                if (canManage) ...[const SizedBox(height: 6), _DeviceActions(device: device)],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeviceActions extends ConsumerWidget {
  const _DeviceActions({required this.device});

  final BiometricDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Edit',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => DeviceFormDialog(device: device),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: 'Remove',
          onPressed: () async {
            final sure = await confirmDialog(
              context,
              title: 'Remove device?',
              message:
                  'This removes "${device.name}" (${device.serialNumber}) from the register of devices. '
                  'The device itself is not changed; it will simply no longer be recognised.',
              confirmLabel: 'Remove',
              isDestructive: true,
            );

            if (!sure || !context.mounted) return;

            try {
              await ref.read(devicePageNotifierProvider.notifier).removeDevice(device);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          },
        ),
      ],
    );
  }
}
