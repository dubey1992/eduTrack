import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/date_period.dart';
import '../../../core/widgets/period_filter.dart';
import '../../reports/data/models/report.dart';
import '../application/staff_attendance_period_provider.dart';
import '../../../core/errors/failure.dart';
import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../departments/application/department_picker_provider.dart';
import '../../departments/data/models/department.dart';
import '../application/staff_attendance_register_notifier.dart';
import '../data/models/staff_attendance_register.dart';
import '../data/models/staff_attendance_status.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/school_picker.dart';

/// Mark or edit a school's daily staff attendance register - Phase 8,
/// reusing the existing school/department pickers from Super Admin (Phase 2)
/// and Academic Config (Phase 4) rather than introducing a parallel
/// selection flow, the same approach Student Attendance (Phase 7) took.
class StaffAttendanceScreen extends ConsumerStatefulWidget {
  const StaffAttendanceScreen({super.key});

  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  int? _schoolId;
  int? _departmentId;

  /// Null until the user picks a day; the school's today stands in until
  /// then. Resolved on build rather than in initState, because the session
  /// (and with it the school's clock) may still be loading when this screen
  /// is first mounted.
  DateTime? _pickedDate;

  /// A day is the register; a week or a month is each person's totals.
  DatePeriod _period = DatePeriod.day;

  DateTime get _date => _pickedDate ?? ref.read(schoolClockProvider).today;

  String get _formattedDate => DateFormat('yyyy-MM-dd').format(_date);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: ref.read(schoolClockProvider).today,
    );
    if (picked != null) setState(() => _pickedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    final role = actor?.role;
    final picksSchool = actor?.picksSchool ?? false;
    final isHod = role == UserRole.hod;
    // An HOD's roster is always their own department(s), server-side - the
    // department picker would have no visible effect, so it's not shown.
    final showDepartmentPicker = !isHod;
    final ready = !picksSchool || _schoolId != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Staff Attendance', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Daily teacher and staff attendance register.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          PeriodFilter(
            value: _period,
            periods: const [DatePeriod.day, DatePeriod.week, DatePeriod.month],
            onChanged: (period) => setState(() => _period = period),
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
                          _departmentId = null;
                        }),
                      ),
                    ),
                  if (showDepartmentPicker && ready)
                    SizedBox(
                      width: 220,
                      child: _DepartmentPicker(
                        schoolId: _schoolId,
                        selected: _departmentId,
                        onChanged: (value) => setState(() => _departmentId = value),
                      ),
                    ),
                  if (_period == DatePeriod.day)
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(formatDate(_date)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (ready && _period != DatePeriod.day) _periodSummary(),
          if (ready && _period == DatePeriod.day) ...[
            _RegisterView(
              key: ValueKey('$_schoolId-$_departmentId-$_formattedDate'),
              params: StaffAttendanceRegisterParams(
                schoolId: _schoolId,
                departmentId: _departmentId,
                date: _formattedDate,
              ),
            ),
            const SizedBox(height: 20),
            _CheckInLog(
              params: StaffAttendanceRegisterParams(
                schoolId: _schoolId,
                departmentId: _departmentId,
                date: _formattedDate,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The week or month so far: from its first day to the school's today,
  /// since the report refuses days still to come.
  Widget _periodSummary() {
    final today = ref.read(schoolClockProvider).today;
    final range = _period.rangeFrom(today)!;

    return _PeriodSummary(
      period: _period,
      params: (
        schoolId: _schoolId,
        departmentId: _departmentId,
        from: range.from,
        to: DateFormat('yyyy-MM-dd').format(today),
      ),
    );
  }
}

/// Each person's present / half day / absent / leave / unmarked days over
/// a week or a month, out of the school days so far.
class _PeriodSummary extends ConsumerWidget {
  const _PeriodSummary({required this.period, required this.params});

  final DatePeriod period;
  final StaffAttendancePeriodParams params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<ReportResult>(
      value: ref.watch(staffAttendancePeriodProvider(params)),
      onRetry: () => ref.invalidate(staffAttendancePeriodProvider(params)),
      isEmpty: (summary) => summary.rows.isEmpty,
      emptyBuilder: (context) => const Card(
        key: Key('staff-period-empty'),
        child: Padding(padding: EdgeInsets.all(20), child: Text('No staff to show.')),
      ),
      data: (context, summary) {
        final days = summary.totals['working_days'] ?? 0;

        return Card(
          key: const Key('staff-period-summary'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${period.label}: ${days == 1 ? '1 school day' : '$days school days'} so far',
                  key: const Key('staff-period-days'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                HorizontalScrollTable(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Department')),
                      DataColumn(label: Text('Present'), numeric: true),
                      DataColumn(label: Text('Half day'), numeric: true),
                      DataColumn(label: Text('Absent'), numeric: true),
                      DataColumn(label: Text('Leave'), numeric: true),
                      DataColumn(label: Text('Unmarked'), numeric: true),
                      DataColumn(label: Text('Attendance'), numeric: true),
                    ],
                    rows: [
                      for (final row in summary.rows)
                        DataRow(
                          key: ValueKey('staff-period-${row['staff_profile_id']}'),
                          cells: [
                            DataCell(Text('${row['name']}')),
                            DataCell(Text('${row['department'] ?? '-'}')),
                            DataCell(Text('${row['present'] ?? 0}')),
                            DataCell(Text('${row['half_day'] ?? 0}')),
                            DataCell(Text('${row['absent'] ?? 0}')),
                            DataCell(Text('${row['leave'] ?? 0}')),
                            DataCell(Text('${row['not_marked'] ?? 0}')),
                            DataCell(Text('${row['attendance_rate']}%')),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DepartmentPicker extends ConsumerWidget {
  const _DepartmentPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departmentsState = ref.watch(departmentPickerProvider(schoolId));

    return AsyncValueView<List<Department>>(
      value: departmentsState,
      data: (context, departments) {
        return DropdownButtonFormField<int>(
          initialValue: departments.any((d) => d.id == selected) ? selected : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Department'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All Departments')),
            for (final department in departments) DropdownMenuItem(value: department.id, child: Text(department.name)),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

class _RegisterView extends ConsumerWidget {
  const _RegisterView({super.key, required this.params});

  final StaffAttendanceRegisterParams params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registerState = ref.watch(staffAttendanceRegisterProvider(params));
    final notifier = ref.read(staffAttendanceRegisterProvider(params).notifier);
    final canMark = ref.watch(authNotifierProvider).value?.canManage(AppModules.staffAttendance) ?? false;

    return AsyncValueView<StaffAttendanceRegister>(
      value: registerState,
      onRetry: () => ref.invalidate(staffAttendanceRegisterProvider(params)),
      isEmpty: (register) => register.staff.isEmpty,
      emptyBuilder: (context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No active staff to mark for this selection.')),
        ),
      ),
      data: (context, register) {
        final isComplete = register.staff.every((s) => s.status != null);
        // On a holiday the server refuses to mark, so the whole register is
        // read-only and the banner explains why instead of the submit row.
        final holiday = register.holiday;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                'Attendance is not marked on holidays. Pick another date to mark staff.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (final entry in register.staff)
                    _StaffRosterRow(
                      key: ValueKey(entry.staffProfileId),
                      entry: entry,
                      enabled: holiday == null && canMark,
                      onStatusChanged: (status) => notifier.setStatus(entry.staffProfileId, status),
                      onCheckInChanged: (time) => notifier.setCheckIn(entry.staffProfileId, time),
                      onCheckOutChanged: (time) => notifier.setCheckOut(entry.staffProfileId, time),
                      onRemarksChanged: (remarks) => notifier.setRemarks(entry.staffProfileId, remarks),
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

class _StaffRosterRow extends StatefulWidget {
  const _StaffRosterRow({
    super.key,
    required this.entry,
    required this.enabled,
    required this.onStatusChanged,
    required this.onCheckInChanged,
    required this.onCheckOutChanged,
    required this.onRemarksChanged,
  });

  final StaffRosterEntry entry;

  /// False when the register is read-only (a holiday).
  final bool enabled;
  final ValueChanged<StaffAttendanceStatus> onStatusChanged;
  final ValueChanged<String?> onCheckInChanged;
  final ValueChanged<String?> onCheckOutChanged;
  final ValueChanged<String?> onRemarksChanged;

  @override
  State<_StaffRosterRow> createState() => _StaffRosterRowState();
}

class _StaffRosterRowState extends State<_StaffRosterRow> {
  late final _remarksController = TextEditingController(text: widget.entry.remarks ?? '');

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(ValueChanged<String?> onChanged, String? current) async {
    final initial = current == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: int.parse(current.split(':')[0]), minute: int.parse(current.split(':')[1]));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    onChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${entry.employeeId} · ${entry.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (entry.departmentName != null)
                      Text(
                        entry.departmentName!,
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              for (final status in StaffAttendanceStatus.values)
                ChoiceChip(
                  label: Text(status.label[0]),
                  tooltip: status.label,
                  selected: entry.status == status,
                  onSelected: widget.enabled ? (_) => widget.onStatusChanged(status) : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: widget.enabled ? () => _pickTime(widget.onCheckInChanged, entry.checkIn) : null,
                icon: const Icon(Icons.login, size: 16),
                label: Text(entry.checkIn ?? 'Check In'),
              ),
              OutlinedButton.icon(
                onPressed: widget.enabled ? () => _pickTime(widget.onCheckOutChanged, entry.checkOut) : null,
                icon: const Icon(Icons.logout, size: 16),
                label: Text(entry.checkOut ?? 'Check Out'),
              ),
              if (entry.workingHours != null) Text('Worked: ${entry.workingHours}'),
              // Said, not left to be guessed: a day a reader marked, or times
              // that came off one, is not the same as a day somebody decided
              // (docs/biometric.md, B3 and B5). Whoever opens this should
              // know which they are looking at before they leave it alone.
              if (entry.markedByDevice)
                _DeviceNote(
                  label: 'Marked from the device',
                  tooltip: 'Marked Present by a punch on the fingerprint reader. Change it if it is wrong.',
                )
              else if (entry.timesFromDevice)
                _DeviceNote(
                  label: 'From the device',
                  tooltip: 'First and last punch on the fingerprint reader. Change them if they are wrong.',
                )
              // The person checked themselves in from the School365ai app,
              // within the school's distance (docs/staff-check-in.md).
              else if (entry.checkedInFromApp)
                _DeviceNote(
                  key: ValueKey('from-app-${entry.staffProfileId}'),
                  label: 'From the app',
                  icon: Icons.phone_android,
                  tooltip: 'Checked in from the School365ai app at school. Change it if it is wrong.',
                ),
              if (entry.late)
                Tooltip(
                  message: 'Checked in after the first period of the day.',
                  child: Chip(
                    label: const Text('Late'),
                    labelStyle: TextStyle(fontSize: 12, color: context.appColors.warning),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: context.appColors.warning),
                    backgroundColor: Colors.transparent,
                  ),
                ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _remarksController,
                  enabled: widget.enabled,
                  decoration: const InputDecoration(labelText: 'Remarks (optional)', isDense: true),
                  onChanged: (value) => widget.onRemarksChanged(value.trim().isEmpty ? null : value.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "This came off a reader, not from a person."
class _DeviceNote extends StatelessWidget {
  const _DeviceNote({super.key, required this.label, required this.tooltip, this.icon = Icons.fingerprint});

  final String label;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: colour)),
        ],
      ),
    );
  }
}

/// Every check-in and check-out made from the School365ai app on the chosen
/// day, in the order they happened (docs/staff-check-in.md). What the phone
/// recorded at the tap - if the office corrected the day above, this still
/// shows what the phone said - with how far from school it was.
class _CheckInLog extends ConsumerWidget {
  const _CheckInLog({required this.params});

  final StaffAttendanceRegisterParams params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(staffCheckInLogProvider(params));
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Card(
      key: const Key('check-in-log'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_android, size: 20),
                const SizedBox(width: 8),
                Text('App check-ins', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text('Check-ins and check-outs made from the School365ai app at school, as recorded.', style: muted),
            const SizedBox(height: 12),
            log.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Row(
                children: [
                  Expanded(child: Text('The app check-ins could not be loaded.', style: muted)),
                  TextButton(
                    onPressed: () => ref.invalidate(staffCheckInLogProvider(params)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (events) => events.isEmpty
                  ? Text(
                      'Nobody has checked in from the app on this day.',
                      key: const Key('check-in-log-empty'),
                      style: muted,
                    )
                  : HorizontalScrollTable(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Time')),
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Department')),
                          DataColumn(label: Text('Event')),
                          DataColumn(label: Text('From school')),
                        ],
                        rows: [
                          for (final event in events)
                            DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    event.time == null ? '-' : formatClock(event.time!),
                                    key: ValueKey('check-in-event-${event.id}'),
                                  ),
                                ),
                                DataCell(Text('${event.name} (${event.employeeId})')),
                                DataCell(Text(event.departmentName ?? '-')),
                                DataCell(
                                  StatusBadge(
                                    label: event.isCheckIn ? 'Checked in' : 'Checked out',
                                    tone: event.isCheckIn ? BadgeTone.success : BadgeTone.neutral,
                                  ),
                                ),
                                DataCell(Text(event.distanceMetres == null ? '-' : '${event.distanceMetres} m')),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
