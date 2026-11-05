import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../academic_years/application/viewed_year.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../application/attendance_register_notifier.dart';
import '../data/models/attendance_register.dart';
import '../data/models/attendance_status.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/school_picker.dart';

/// Mark or edit a class's daily attendance register - the Teacher/Admin
/// workflow behind CLAUDE.md's Phase 7 (Student Attendance), reusing the
/// existing school/class-section pickers from Academic Config (Phase 4)
/// rather than introducing a parallel selection flow.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  int? _schoolId;
  int? _classSectionId;

  /// Null until the user picks a day; the school's today stands in until
  /// then. Resolved on build rather than in initState, because the session
  /// (and with it the school's clock) may still be loading when this screen
  /// is first mounted.
  DateTime? _pickedDate;

  DateTime get _date => _pickedDate ?? _lastDay;

  String get _formattedDate => DateFormat('yyyy-MM-dd').format(_date);

  /// The top bar's year (decided 2026-11-05), for somebody who has one. A
  /// Super Admin picking a school sees that school's current year.
  AcademicYear? get _year => _schoolId == null ? ref.read(viewedYearProvider).value : null;

  /// The latest day a register can be read: today, or the last day of a
  /// year that has ended.
  DateTime get _lastDay {
    final today = ref.read(schoolClockProvider).today;
    final year = _year;
    return year != null && year.endDate.isBefore(today) ? year.endDate : today;
  }

  /// A year that has not begun has no register to read yet.
  bool get _yearNotBegun {
    final year = _year;
    return year != null && year.startDate.isAfter(ref.read(schoolClockProvider).today);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _year?.startDate ?? DateTime(2020),
      lastDate: _lastDay,
    );
    if (picked != null) setState(() => _pickedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    final picksSchool = actor?.picksSchool ?? false;
    ref.watch(viewedYearProvider);
    // Another year: its own sections and days, nothing carried over.
    ref.listen(viewedYearIdProvider, (previous, next) {
      setState(() {
        _pickedDate = null;
        _classSectionId = null;
      });
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Student Attendance', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Daily class attendance register.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Card(
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
                  if (!picksSchool || _schoolId != null)
                    SizedBox(
                      width: 240,
                      child: _ClassSectionPicker(
                        schoolId: _schoolId,
                        year: _year,
                        selected: _classSectionId,
                        onChanged: (value) => setState(() => _classSectionId = value),
                      ),
                    ),
                  OutlinedButton.icon(
                    key: const Key('attendance-date'),
                    onPressed: _yearNotBegun ? null : _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(formatDate(_date)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_yearNotBegun)
            Card(
              key: const Key('attendance-year-not-begun'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${_year?.name} has not begun yet, so it has no attendance to show.'),
              ),
            )
          else if (_classSectionId != null)
            _RegisterView(
              key: ValueKey('$_classSectionId-$_formattedDate'),
              params: AttendanceRegisterParams(classSectionId: _classSectionId!, date: _formattedDate),
            ),
        ],
      ),
    );
  }
}

class _ClassSectionPicker extends ConsumerWidget {
  const _ClassSectionPicker({required this.schoolId, required this.selected, required this.onChanged, this.year});

  final int? schoolId;

  /// A year other than the current one lists that year's sections.
  final AcademicYear? year;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authNotifierProvider).value?.role;
    final userId = ref.watch(authNotifierProvider).value?.id;
    final other = year != null && !year!.isCurrent;
    final optionsState = other
        ? ref.watch(classSectionsOfYearProvider(year!.id))
        : ref.watch(classSectionPickerProvider(schoolId));

    return AsyncValueView<List<ClassSectionOption>>(
      value: optionsState,
      data: (context, options) {
        // A teacher only ever marks attendance for a section they're the
        // class teacher of - narrow the shared picker down client-side
        // rather than standing up a parallel "my sections" endpoint.
        final visible = role == UserRole.teacher ? options.where((o) => o.classTeacherId == userId).toList() : options;

        return DropdownButtonFormField<int>(
          initialValue: visible.any((o) => o.id == selected) ? selected : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class'),
          items: [for (final option in visible) DropdownMenuItem(value: option.id, child: Text(option.label))],
          onChanged: onChanged,
        );
      },
    );
  }
}

class _RegisterView extends ConsumerWidget {
  const _RegisterView({super.key, required this.params});

  final AttendanceRegisterParams params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registerState = ref.watch(attendanceRegisterProvider(params));
    final notifier = ref.read(attendanceRegisterProvider(params).notifier);
    final canMark = ref.watch(authNotifierProvider).value?.canManage(AppModules.attendance) ?? false;

    return AsyncValueView<AttendanceRegister>(
      value: registerState,
      onRetry: () => ref.invalidate(attendanceRegisterProvider(params)),
      isEmpty: (register) => register.students.isEmpty,
      emptyBuilder: (context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No active students in this class.')),
        ),
      ),
      data: (context, register) {
        final isComplete = register.students.every((s) => s.status != null);
        // On a holiday the server refuses to mark, so the whole register is
        // read-only and the banner explains why instead of the submit row.
        final holiday = register.holiday;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A plain Row here hard-overflows once the chip + both buttons'
            // natural widths exceed the available space (same class of bug
            // fixed on the marketing footer/nav bar earlier - a fixed-width
            // Row with no flex can't just shrink). Wrap lets the button
            // group drop to its own line on a narrow viewport instead.
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (holiday != null)
                  Chip(
                    avatar: Icon(Icons.beach_access_outlined, size: 18, color: context.appColors.onDangerContainer),
                    label: Text('Holiday: ${holiday.name}'),
                    backgroundColor: context.appColors.dangerContainer,
                    labelStyle: TextStyle(color: context.appColors.onDangerContainer),
                  )
                else
                  Chip(
                    label: Text(register.submitted ? 'Submitted' : 'Not yet submitted'),
                    backgroundColor: register.submitted
                        ? context.appColors.successContainer
                        : context.appColors.warningContainer,
                    labelStyle: TextStyle(
                      color: register.submitted
                          ? context.appColors.onSuccessContainer
                          : context.appColors.onWarningContainer,
                    ),
                  ),
                if (holiday == null && canMark)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(onPressed: notifier.markAllPresent, child: const Text('Mark All Present')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: isComplete
                            ? () async {
                                try {
                                  await notifier.submitOrUpdate();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          register.submitted ? 'Attendance updated.' : 'Attendance submitted.',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (error) {
                                  final failure = error is Failure ? error : Failure.unknown(error.toString());
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(content: Text(failure.message)));
                                  }
                                }
                              }
                            : null,
                        child: Text(register.submitted ? 'Update Attendance' : 'Submit Attendance'),
                      ),
                    ],
                  ),
              ],
            ),
            if (holiday != null) ...[
              const SizedBox(height: 8),
              Text(
                'Attendance is not marked on holidays. Pick another date to mark this class.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (final entry in register.students)
                    _RosterRow(
                      entry: entry,
                      onStatusChanged: holiday != null ? null : (status) => notifier.setStatus(entry.studentId, status),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({required this.entry, required this.onStatusChanged});

  final AttendanceRosterEntry entry;

  /// Null when the register is read-only (a holiday).
  final ValueChanged<AttendanceStatus>? onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (entry.rollNumber != null)
                  Text(
                    'Roll No. ${entry.rollNumber}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          for (final status in AttendanceStatus.values)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                label: Text(status.label[0]),
                tooltip: status.label,
                selected: entry.status == status,
                onSelected: onStatusChanged == null ? null : (_) => onStatusChanged!(status),
              ),
            ),
        ],
      ),
    );
  }
}
