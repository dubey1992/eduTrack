import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../departments/application/department_picker_provider.dart';
import '../../departments/data/models/department.dart';
import '../../schools/application/school_list_notifier.dart';
import '../../schools/data/models/school.dart';
import '../application/staff_attendance_register_notifier.dart';
import '../data/models/staff_attendance_register.dart';
import '../data/models/staff_attendance_status.dart';

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
    final role = ref.watch(authNotifierProvider).value?.role;
    final isSuperAdmin = role == UserRole.superAdmin;
    final isHod = role == UserRole.hod;
    // An HOD's roster is always their own department(s), server-side - the
    // department picker would have no visible effect, so it's not shown.
    final showDepartmentPicker = !isHod;
    final ready = !isSuperAdmin || _schoolId != null;

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
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isSuperAdmin)
                    SizedBox(
                      width: 240,
                      child: _SchoolPicker(
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
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(DateFormat.yMMMd().format(_date)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (ready)
            _RegisterView(
              key: ValueKey('$_schoolId-$_departmentId-$_formattedDate'),
              params: StaffAttendanceRegisterParams(
                schoolId: _schoolId,
                departmentId: _departmentId,
                date: _formattedDate,
              ),
            ),
        ],
      ),
    );
  }
}

class _SchoolPicker extends ConsumerWidget {
  const _SchoolPicker({required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolsState = ref.watch(schoolListNotifierProvider);

    return AsyncValueView<List<School>>(
      value: schoolsState,
      data: (context, schools) {
        final activeSchools = schools.where((s) => s.status == SchoolStatus.active);
        return DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'School'),
          items: [
            for (final school in activeSchools)
              DropdownMenuItem(
                value: school.id,
                child: Text(school.name, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
          ],
          onChanged: onChanged,
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
                if (holiday == null)
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
                      enabled: holiday == null,
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
