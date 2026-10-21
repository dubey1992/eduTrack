import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../application/punch_page_notifier.dart';
import '../data/models/biometric_punch.dart';

/// What the devices have recorded (docs/biometric.md, B2).
///
/// The reason somebody opens this rather than the register is the
/// unattributed punches: ids no device user has been mapped to. They are
/// counted above the list and can be shown on their own, because they are
/// the work this screen exists to surface.
class PunchLogView extends ConsumerStatefulWidget {
  const PunchLogView({super.key});

  @override
  ConsumerState<PunchLogView> createState() => _PunchLogViewState();
}

class _PunchLogViewState extends ConsumerState<PunchLogView> {
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
      ref.read(punchPageNotifierProvider.notifier).setSearch(term);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(punchPageNotifierProvider);
    final notifier = ref.read(punchPageNotifierProvider.notifier);
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    labelText: 'Search the log',
                    hintText: 'Name, employee ID or device ID',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                  ),
                  onChanged: _search,
                ),
              ),
              FilterChip(
                key: const Key('unattributed-only'),
                label: const Text('Nobody mapped'),
                selected: notifier.unmatchedOnly,
                onSelected: (only) => notifier.setUnmatchedOnly(only),
              ),
            ],
          ),
        ),
        // Said above the list, under the same filters, because a page of
        // twenty cannot tell "none here" from "none at all".
        if (notifier.unmatchedTotal > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              notifier.unmatchedTotal == 1
                  ? '1 punch belongs to a device ID nobody has been mapped to. '
                        'Enrolling that person attaches it.'
                  : '${notifier.unmatchedTotal} punches belong to device IDs nobody has been mapped to. '
                        'Enrolling those people attaches them.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.warning),
            ),
          ),
        Expanded(
          child: AsyncValueView<PagedList<BiometricPunch>>(
            value: state,
            onRetry: notifier.refresh,
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No punches recorded yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _PunchCards(punches: page.items),
                      desktop: (context) => _PunchTable(punches: page.items),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: notifier.goToPage,
                    onPerPageChanged: notifier.setPerPage,
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

/// Who the punch belongs to, or a plain statement that nobody knows.
///
/// Not a blank: an unattributed punch is work for somebody, and a blank
/// reads as an absence of information rather than a thing to go and fix.
Widget whose(BuildContext context, BiometricPunch punch) {
  if (punch.isUnattributed) {
    return Text('Nobody mapped to ${punch.biometricUserId}', style: TextStyle(color: context.appColors.warning));
  }

  return Text(punch.staffName ?? '-');
}

class _PunchTable extends StatelessWidget {
  const _PunchTable({required this.punches});

  final List<BiometricPunch> punches;

  @override
  Widget build(BuildContext context) {
    return HorizontalScrollTable(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('When')),
          DataColumn(label: Text('Who')),
          DataColumn(label: Text('Employee ID')),
          DataColumn(label: Text('Device ID')),
          DataColumn(label: Text('Device')),
        ],
        rows: [
          for (final punch in punches)
            DataRow(
              cells: [
                DataCell(Text(punch.punchedAtLabel)),
                DataCell(whose(context, punch)),
                DataCell(Text(punch.employeeId ?? '-')),
                DataCell(Text(punch.biometricUserId)),
                // An uploaded file names the person and the time, not which
                // reader they used.
                DataCell(Text(punch.deviceName ?? 'Uploaded')),
              ],
            ),
        ],
      ),
    );
  }
}

class _PunchCards extends StatelessWidget {
  const _PunchCards({required this.punches});

  final List<BiometricPunch> punches;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: punches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final punch = punches[index];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(punch.punchedAtLabel, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                whose(context, punch),
                Text('Device ID ${punch.biometricUserId}', style: TextStyle(color: context.appColors.muted)),
              ],
            ),
          ),
        );
      },
    );
  }
}
