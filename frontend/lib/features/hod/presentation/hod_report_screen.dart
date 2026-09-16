import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../../departments/application/department_picker_provider.dart';
import '../../departments/data/models/department.dart';
import '../application/hod_report_notifier.dart';
import '../data/models/hod_department_report.dart';
import 'widgets/month_stepper.dart';

/// Phase 13 - the prototype's "HOD / Staff Reports" page: one month of a
/// department's teaching performance. An HOD is scoped server-side to the
/// department(s) they head; admins pick a department (or see the whole
/// school). Everything shown is computed on the backend - see
/// HodReportService for the definitions.
class HodReportScreen extends ConsumerStatefulWidget {
  const HodReportScreen({super.key});

  @override
  ConsumerState<HodReportScreen> createState() => _HodReportScreenState();
}

class _HodReportScreenState extends ConsumerState<HodReportScreen> {
  int? _schoolId;
  int? _departmentId;

  /// Null until the user steps to another month; the school's current month
  /// stands in until then, resolved on build so a session that is still
  /// loading cannot pin this to the browser's month.
  DateTime? _chosenMonth;

  DateTime get _month => _chosenMonth ?? _schoolMonth;

  DateTime get _schoolMonth {
    final today = ref.read(schoolClockProvider).today;

    return DateTime(today.year, today.month);
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    if (actor == null) return const SizedBox.shrink();

    final picksSchool = actor.picksSchool;
    final isHod = actor.role == UserRole.hod;
    final needsSchool = picksSchool && _schoolId == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('HOD / Staff Reports', style: Theme.of(context).textTheme.headlineSmall),
              SchoolFilterDropdown(
                selected: _schoolId,
                onChanged: (schoolId) => setState(() {
                  _schoolId = schoolId;
                  _departmentId = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Attendance and teaching performance by department for the selected month.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!isHod)
                    SizedBox(
                      width: 240,
                      child: _DepartmentPicker(
                        schoolId: _schoolId,
                        selected: _departmentId,
                        onChanged: (value) => setState(() => _departmentId = value),
                      ),
                    ),
                  MonthStepper(
                    month: _month,
                    // The newest month a school can report on is its own
                    // current month, which may not be the server's.
                    maxMonth: _schoolMonth,
                    onChanged: (month) => setState(() => _chosenMonth = month),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (needsSchool)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Pick a school to view its report.')),
              ),
            )
          else
            _ReportBody(
              params: HodReportParams(
                schoolId: _schoolId,
                departmentId: _departmentId,
                month: DateFormat('yyyy-MM').format(_month),
              ),
              showDepartmentLabel: isHod,
            ),
        ],
      ),
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
    final departments = ref.watch(departmentPickerProvider(schoolId)).value ?? const <Department>[];

    return DropdownButtonFormField<int?>(
      initialValue: departments.any((d) => d.id == selected) ? selected : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Department', isDense: true),
      items: [
        const DropdownMenuItem(value: null, child: Text('All Departments')),
        for (final department in departments)
          DropdownMenuItem(
            value: department.id,
            child: Text(department.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.params, required this.showDepartmentLabel});

  final HodReportParams params;
  final bool showDepartmentLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportState = ref.watch(hodReportNotifierProvider(params));

    return AsyncValueView<HodDepartmentReport>(
      value: reportState,
      onRetry: () => ref.invalidate(hodReportNotifierProvider(params)),
      data: (context, report) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDepartmentLabel && report.departments.isNotEmpty) ...[
              Text(
                'Department: ${report.departments.map((d) => d.name).join(', ')}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                KpiCard(label: 'Working Days', value: '${report.workingDays}'),
                KpiCard(label: 'Avg. Attendance', value: '${_compact(report.avgAttendancePercent)}%'),
                KpiCard(label: 'Leave Days', value: _compact(report.leaveDays)),
                KpiCard(label: 'Late Marks', value: '${report.lateMarks}'),
                KpiCard(label: 'Teachers', value: '${report.teacherCount}'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Teacher Performance & Attendance', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (report.teachers.isEmpty)
              const Card(
                child: Padding(padding: EdgeInsets.all(20), child: Text('No teachers found for this selection.')),
              )
            else ...[
              ResponsiveBuilder(
                mobile: (context) => _TeacherCards(rows: report.teachers),
                desktop: (context) => _TeacherTable(rows: report.teachers),
              ),
              PaginationControls(
                currentPage: report.currentPage,
                lastPage: report.lastPage,
                total: report.total,
                perPage: report.perPage,
                onPageChanged: (p) => ref.read(hodReportNotifierProvider(params).notifier).goToPage(p),
                onPerPageChanged: (p) => ref.read(hodReportNotifierProvider(params).notifier).setPerPage(p),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 95.0 -> "95", 95.6 -> "95.6" - keeps whole numbers from reading as "95.0".
String _compact(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();

String _reportsLabel(HodTeacherRow row) {
  return row.reportsPendingReview > 0
      ? '${row.reportsSubmitted} (${row.reportsPendingReview} pending)'
      : '${row.reportsSubmitted}';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final HodTeacherStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status.label,
      tone: status == HodTeacherStatus.onTrack ? BadgeTone.success : BadgeTone.warning,
    );
  }
}

class _TeacherTable extends StatefulWidget {
  const _TeacherTable({required this.rows});

  final List<HodTeacherRow> rows;

  @override
  State<_TeacherTable> createState() => _TeacherTableState();
}

class _TeacherTableState extends State<_TeacherTable> {
  // Ten columns rarely fit even a laptop-width content area; a visible
  // thumb is the only hint that the right-hand columns exist.
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;

    return Card(
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Teacher')),
              DataColumn(label: Text('Department')),
              DataColumn(label: Text('Attendance')),
              DataColumn(label: Text('Leave')),
              DataColumn(label: Text('Late')),
              DataColumn(label: Text('Classes Assigned')),
              DataColumn(label: Text('Classes Taught')),
              DataColumn(label: Text('Reports')),
              DataColumn(label: Text('Syllabus')),
              DataColumn(label: Text('HOD Status')),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    DataCell(Text(row.teacherName)),
                    DataCell(Text(row.departmentName ?? '—')),
                    DataCell(Text('${_compact(row.attendancePercent)}%')),
                    DataCell(Text('${_compact(row.leaveDays)} ${row.leaveDays == 1 ? 'day' : 'days'}')),
                    DataCell(Text('${row.lateMarks}')),
                    DataCell(Text('${row.classesAssigned}')),
                    DataCell(Text('${row.classesTaught}')),
                    DataCell(Text(_reportsLabel(row))),
                    DataCell(Text('${row.syllabusPercent}%')),
                    DataCell(_StatusBadge(status: row.status)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeacherCards extends StatelessWidget {
  const _TeacherCards({required this.rows});

  final List<HodTeacherRow> rows;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(row.teacherName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    _StatusBadge(status: row.status),
                  ],
                ),
                if (row.departmentName != null) Text(row.departmentName!, style: muted),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('Attendance ${_compact(row.attendancePercent)}%'),
                    Text('Leave ${_compact(row.leaveDays)}'),
                    Text('Late ${row.lateMarks}'),
                    Text('Assigned ${row.classesAssigned}'),
                    Text('Taught ${row.classesTaught}'),
                    Text('Reports ${_reportsLabel(row)}'),
                    Text('Syllabus ${row.syllabusPercent}%'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
