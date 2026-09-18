import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../application/audit_log_notifier.dart';
import '../data/audit_log_repository.dart';
import '../data/models/audit_entry.dart';
import 'audit_entry_dialog.dart';

/// Phase 21 - the audit trail: who changed what, and when. Read-only; the
/// entries are written by the backend as the changes happen.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  int? _schoolFilter;
  String? _moduleFilter;
  DateTimeRange? _range;
  bool _exporting = false;

  AuditLogNotifier get _notifier => ref.read(auditLogNotifierProvider.notifier);

  Future<void> _pickRange() async {
    final today = ref.read(schoolClockProvider).today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      // Nothing has been recorded after today.
      lastDate: today,
      initialDateRange: _range,
      helpText: 'Changes made between',
    );

    if (picked != null) _setRange(picked);
  }

  void _setRange(DateTimeRange? range) {
    setState(() => _range = range);
    _notifier.setDateRange(
      from: range == null ? null : apiDate(range.start),
      to: range == null ? null : apiDate(range.end),
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final filter = _notifier.filter;
      final bytes = await ref
          .read(auditLogRepositoryProvider)
          .downloadCsv(schoolId: filter.schoolId, module: filter.module, from: filter.from, to: filter.to);

      saveBytes(fileName: 'audit-log.csv', bytes: bytes, mimeType: 'text/csv');

      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Audit log downloaded.')));
    } catch (error) {
      final message = error is Failure ? error.message : error.toString().replaceFirst('UnsupportedError: ', '');
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authNotifierProvider).value?.role;
    // A School Admin's trail is their own school's; the column would say the
    // same thing on every row.
    final showSchool = role == UserRole.superAdmin || role == UserRole.groupAdmin;
    final logState = ref.watch(auditLogNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Audit Log',
          actions: [
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                _notifier.setSchoolFilter(schoolId);
              },
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                key: const Key('audit-module-filter'),
                initialValue: _moduleFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Module', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All modules')),
                  for (final module in AuditModule.values)
                    DropdownMenuItem(
                      value: module.apiValue,
                      child: Text(module.label, overflow: TextOverflow.ellipsis, maxLines: 1),
                    ),
                ],
                onChanged: (module) {
                  setState(() => _moduleFilter = module);
                  _notifier.setModuleFilter(module);
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(_range == null ? 'All dates' : '${formatDate(_range!.start)} - ${formatDate(_range!.end)}'),
            ),
            if (_range != null)
              IconButton(tooltip: 'Clear dates', onPressed: () => _setRange(null), icon: const Icon(Icons.close)),
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined, size: 18),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<AuditEntry>>(
            value: logState,
            onRetry: () => _notifier.refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(
              child: Padding(padding: EdgeInsets.all(32), child: Text('No audit entries match these filters.')),
            ),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _AuditListMobile(entries: page.items, showSchool: showSchool),
                      desktop: (context) => _AuditListDesktop(entries: page.items, showSchool: showSchool),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => _notifier.goToPage(p),
                    onPerPageChanged: (p) => _notifier.setPerPage(p),
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

void _openEntry(BuildContext context, AuditEntry entry, {required bool showSchool}) {
  showDialog<void>(
    context: context,
    builder: (_) => AuditEntryDialog(entry: entry, showSchool: showSchool),
  );
}

/// The actor's name over their role, in one cell.
class _ActorText extends StatelessWidget {
  const _ActorText({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final role = entry.roleLabel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.actorLabel, overflow: TextOverflow.ellipsis),
        if (role != null) Text(role, style: TextStyle(fontSize: 12, color: context.appColors.muted)),
      ],
    );
  }
}

class _AuditListMobile extends StatelessWidget {
  const _AuditListMobile({required this.entries, required this.showSchool});

  final List<AuditEntry> entries;
  final bool showSchool;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: context.appColors.muted);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final role = entry.roleLabel;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openEntry(context, entry, showSchool: showSchool),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(entry.actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Text(entry.whenLabel, style: muted),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(role == null ? entry.actorLabel : '${entry.actorLabel} · $role'),
                  Text('${entry.moduleLabel} · ${entry.recordLabel}'),
                  if (showSchool) Text(entry.schoolLabel, style: muted),
                  if (entry.ip != null) Text('IP ${entry.ip}', style: muted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AuditListDesktop extends StatelessWidget {
  const _AuditListDesktop({required this.entries, required this.showSchool});

  final List<AuditEntry> entries;
  final bool showSchool;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            showCheckboxColumn: false,
            // Tight enough that the View action stays on screen beside the
            // sidebar at desktop widths; the table still scrolls sideways.
            columnSpacing: 22,
            dataRowMaxHeight: 60,
            columns: [
              const DataColumn(label: Text('When')),
              const DataColumn(label: Text('User')),
              if (showSchool) const DataColumn(label: Text('School')),
              const DataColumn(label: Text('Module')),
              const DataColumn(label: Text('Action')),
              const DataColumn(label: Text('Record')),
              const DataColumn(label: Text('IP')),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final entry in entries)
                DataRow(
                  onSelectChanged: (_) => _openEntry(context, entry, showSchool: showSchool),
                  cells: [
                    DataCell(Text(entry.whenLabel)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: _ActorText(entry: entry),
                      ),
                    ),
                    if (showSchool)
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(entry.schoolLabel, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    DataCell(Text(entry.moduleLabel)),
                    DataCell(Text(entry.actionLabel)),
                    DataCell(Text(entry.recordLabel)),
                    DataCell(Text(entry.ip ?? '-')),
                    DataCell(
                      TextButton(
                        onPressed: () => _openEntry(context, entry, showSchool: showSchool),
                        child: const Text('View'),
                      ),
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
