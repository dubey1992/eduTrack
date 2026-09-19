import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/module_access.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/application/auth_notifier.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../application/period_list_notifier.dart';
import '../application/timetable_grid_notifier.dart';
import '../data/models/day_of_week.dart';
import '../data/models/period.dart';
import '../data/models/timetable_entry.dart';
import 'widgets/edit_entry_dialog.dart';
import 'widgets/manage_periods_dialog.dart';
import '../../../core/widgets/school_picker.dart';

/// Phase 10 - a class section's weekly (Mon-Fri x period) subject/teacher
/// grid, matching the prototype's "Timetable & Period Management" screen.
/// SuperAdmin/SchoolAdmin edit a class section's grid; every other role
/// (Teacher/HOD/Staff/Transport Manager) instead sees "My Schedule" - their
/// own periods across every class section they teach, read-only.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  int? _schoolId;
  int? _classSectionId;

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    if (actor == null) return const SizedBox.shrink();

    final canEdit = actor.canManage(AppModules.timetable);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Timetable', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            canEdit ? 'Class schedules and period management.' : 'Your weekly teaching schedule.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (canEdit) _buildAdminControls(context) else const SizedBox.shrink(),
          const SizedBox(height: 20),
          if (canEdit)
            (_classSectionId != null)
                ? _ClassSectionGrid(
                    key: ValueKey('$_schoolId-$_classSectionId'),
                    schoolId: _schoolId,
                    classSectionId: _classSectionId!,
                  )
                : const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Pick a class section to view its timetable.')),
                    ),
                  )
          else
            _MyScheduleGrid(key: ValueKey(actor.id), teacherId: actor.id),
        ],
      ),
    );
  }

  Widget _buildAdminControls(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (picksSchool)
              SizedBox(
                width: 240,
                child: SchoolPicker(
                  required: false,
                  selected: _schoolId,
                  onChanged: (value) => setState(() {
                    _schoolId = value;
                    _classSectionId = null;
                  }),
                ),
              ),
            SizedBox(
              width: 220,
              child: _ClassSectionPicker(
                schoolId: _schoolId,
                selected: _classSectionId,
                onChanged: (value) => setState(() => _classSectionId = value),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => ManagePeriodsDialog(schoolId: _schoolId),
              ),
              icon: const Icon(Icons.schedule_outlined, size: 18),
              label: const Text('Manage Periods'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassSectionPicker extends ConsumerWidget {
  const _ClassSectionPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsState = ref.watch(classSectionPickerProvider(schoolId));

    return AsyncValueView<List<ClassSectionOption>>(
      value: optionsState,
      data: (context, options) {
        return DropdownButtonFormField<int>(
          initialValue: options.any((o) => o.id == selected) ? selected : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class'),
          items: [for (final option in options) DropdownMenuItem(value: option.id, child: Text(option.label))],
          onChanged: onChanged,
        );
      },
    );
  }
}

class _ClassSectionGrid extends ConsumerWidget {
  const _ClassSectionGrid({super.key, required this.schoolId, required this.classSectionId});

  final int? schoolId;
  final int classSectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = TimetableGridParams.forClassSection(classSectionId);
    final periodsState = ref.watch(periodListNotifierProvider(schoolId));
    final entriesState = ref.watch(timetableGridProvider(params));

    return AsyncValueView<List<Period>>(
      value: periodsState,
      data: (context, periods) {
        if (periods.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Add periods first, then build the timetable.')),
            ),
          );
        }

        return AsyncValueView<List<TimetableEntry>>(
          value: entriesState,
          onRetry: () => ref.invalidate(timetableGridProvider(params)),
          data: (context, entries) {
            return _TimetableGrid(
              periods: periods,
              cellLabel: (entry) => '${entry.subjectName ?? ''}\n${entry.teacherName ?? ''}',
              entryFor: (periodId, day) => entries
                  .where((e) => e.periodId == periodId && e.dayOfWeek == day)
                  .cast<TimetableEntry?>()
                  .firstOrNull,
              onCellTap: (period, day, entry) => showDialog(
                context: context,
                builder: (_) => EditEntryDialog(
                  schoolId: schoolId,
                  classSectionId: classSectionId,
                  periodId: period.id,
                  periodLabel: 'Period ${period.periodNumber}',
                  dayOfWeek: day,
                  existing: entry,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MyScheduleGrid extends ConsumerWidget {
  const _MyScheduleGrid({super.key, required this.teacherId});

  final int teacherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = TimetableGridParams.forTeacher(teacherId);
    final entriesState = ref.watch(timetableGridProvider(params));

    return AsyncValueView<List<TimetableEntry>>(
      value: entriesState,
      onRetry: () => ref.invalidate(timetableGridProvider(params)),
      isEmpty: (entries) => entries.isEmpty,
      emptyBuilder: (context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No periods assigned to you yet.')),
        ),
      ),
      data: (context, entries) {
        final periods = {for (final e in entries) e.periodId: e.periodNumber ?? 0};
        final syntheticPeriods =
            periods.entries
                .map((e) => Period(id: e.key, schoolId: 0, periodNumber: e.value, startTime: '', endTime: ''))
                .toList()
              ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));

        return _TimetableGrid(
          periods: syntheticPeriods,
          cellLabel: (entry) => '${entry.subjectName ?? ''}\n${entry.classSectionName ?? ''}',
          entryFor: (periodId, day) =>
              entries.where((e) => e.periodId == periodId && e.dayOfWeek == day).cast<TimetableEntry?>().firstOrNull,
          onCellTap: null,
        );
      },
    );
  }
}

/// Mon-Fri x period grid, generic enough to serve both the editable
/// class-section view and the read-only "My Schedule" view - [onCellTap]
/// null means read-only.
class _TimetableGrid extends StatelessWidget {
  const _TimetableGrid({
    required this.periods,
    required this.cellLabel,
    required this.entryFor,
    required this.onCellTap,
  });

  final List<Period> periods;
  final String Function(TimetableEntry entry) cellLabel;
  final TimetableEntry? Function(int periodId, DayOfWeek day) entryFor;
  final void Function(Period period, DayOfWeek day, TimetableEntry? existing)? onCellTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant),
          defaultColumnWidth: const FixedColumnWidth(140),
          columnWidths: const {0: FixedColumnWidth(90)},
          children: [
            TableRow(
              decoration: BoxDecoration(color: colors.infoContainer),
              children: [const _HeaderCell('Period'), for (final day in DayOfWeek.values) _HeaderCell(day.label)],
            ),
            for (final period in periods)
              TableRow(
                children: [
                  _HeaderCell(
                    period.startTime.isEmpty
                        ? 'P${period.periodNumber}'
                        : 'P${period.periodNumber}\n${period.startTime}',
                  ),
                  for (final day in DayOfWeek.values) _buildCell(context, period, day),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, Period period, DayOfWeek day) {
    final entry = entryFor(period.id, day);
    final tappable = onCellTap != null;

    return InkWell(
      onTap: tappable ? () => onCellTap!(period, day, entry) : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        height: 56,
        alignment: Alignment.center,
        child: entry == null
            ? (tappable ? const Icon(Icons.add, size: 16) : const SizedBox.shrink())
            : Text(cellLabel(entry), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
