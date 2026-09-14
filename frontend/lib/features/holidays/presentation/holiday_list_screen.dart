import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/holiday_page_notifier.dart';
import '../data/models/holiday.dart';
import 'add_holiday_dialog.dart';
import 'edit_holiday_dialog.dart';
import '../../../core/utils/date_format.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.schoolAdmin};

/// The school's holiday calendar. Everyone can see it (attendance, leave,
/// teaching reports and the HOD report all depend on it); admins define it.
class HolidayListScreen extends ConsumerStatefulWidget {
  const HolidayListScreen({super.key});

  @override
  ConsumerState<HolidayListScreen> createState() => _HolidayListScreenState();
}

class _HolidayListScreenState extends ConsumerState<HolidayListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final holidaysState = ref.watch(holidayPageNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Holidays',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddHolidayDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Holiday'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(holidayPageNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<Holiday>>(
            value: holidaysState,
            onRetry: () => ref.read(holidayPageNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No holidays on the calendar yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _HolidayCards(holidays: page.items, canManage: canManage),
                      desktop: (context) => _HolidayTable(holidays: page.items, canManage: canManage),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(holidayPageNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(holidayPageNotifierProvider.notifier).setPerPage(p),
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

String _dateRange(Holiday holiday) {
  final start = formatDate(DateTime.parse(holiday.startDate));
  if (holiday.isSingleDay) return start;
  return '$start – ${formatDate(DateTime.parse(holiday.endDate))}';
}

String _daysLabel(Holiday holiday) => holiday.days == 1 ? '1 day' : '${holiday.days} days';

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final HolidayType type;

  @override
  Widget build(BuildContext context) {
    final tone = switch (type) {
      HolidayType.national => BadgeTone.info,
      HolidayType.religious => BadgeTone.warning,
      HolidayType.schoolEvent => BadgeTone.success,
      HolidayType.vacation => BadgeTone.neutral,
    };
    return StatusBadge(label: type.label, tone: tone);
  }
}

Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Holiday holiday) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete holiday?'),
      content: Text('This will remove "${holiday.name}" from the calendar. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  // The list re-fetches (and shows its loading state) as part of the delete,
  // which unmounts this row - so resolve the messenger before awaiting.
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(holidayPageNotifierProvider.notifier).deleteHoliday(holiday);
    messenger.showSnackBar(SnackBar(content: Text('${holiday.name} was deleted.')));
  } catch (error) {
    final failure = error is Failure ? error : Failure.unknown(error.toString());
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

class _RowActions extends ConsumerWidget {
  const _RowActions({required this.holiday});

  final Holiday holiday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: 'Edit',
          visualDensity: VisualDensity.compact,
          onPressed: () => showDialog(
            context: context,
            builder: (_) => EditHolidayDialog(holiday: holiday),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: 'Delete',
          visualDensity: VisualDensity.compact,
          onPressed: () => _confirmDelete(context, ref, holiday),
        ),
      ],
    );
  }
}

class _HolidayTable extends StatelessWidget {
  const _HolidayTable({required this.holidays, required this.canManage});

  final List<Holiday> holidays;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Holiday')),
              const DataColumn(label: Text('Type')),
              const DataColumn(label: Text('Dates')),
              const DataColumn(label: Text('Days')),
              if (canManage) const DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final holiday in holidays)
                DataRow(
                  cells: [
                    DataCell(Text(holiday.name)),
                    DataCell(_TypeBadge(type: holiday.type)),
                    DataCell(Text(_dateRange(holiday))),
                    DataCell(Text(_daysLabel(holiday))),
                    if (canManage) DataCell(_RowActions(holiday: holiday)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HolidayCards extends StatelessWidget {
  const _HolidayCards({required this.holidays, required this.canManage});

  final List<Holiday> holidays;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: holidays.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final holiday = holidays[index];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(holiday.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${_dateRange(holiday)} · ${_daysLabel(holiday)}', style: muted),
                      const SizedBox(height: 6),
                      _TypeBadge(type: holiday.type),
                    ],
                  ),
                ),
                if (canManage) _RowActions(holiday: holiday),
              ],
            ),
          ),
        );
      },
    );
  }
}
