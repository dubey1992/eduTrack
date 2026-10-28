import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paginated_response.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/debounced_search_field.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../academic_years/application/academic_year_picker_provider.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/fee_setup_providers.dart';
import '../application/student_fees_providers.dart';
import '../data/models/student_fees.dart';
import '../data/money_text.dart';
import 'widgets/student_statement_view.dart';

/// Student Fees (docs/fees.md, F2): what each student owes for a year, and
/// each one's statement. The student being looked at is in the address
/// (`?student=12`), so the sidebar's check covers it and Back works.
class StudentFeesScreen extends ConsumerStatefulWidget {
  const StudentFeesScreen({super.key, this.studentId});

  final int? studentId;

  @override
  ConsumerState<StudentFeesScreen> createState() => _StudentFeesScreenState();
}

class _StudentFeesScreenState extends ConsumerState<StudentFeesScreen> {
  final _search = TextEditingController();

  int? _schoolId;
  int? _yearId;
  int? _classId;
  String _searchText = '';
  bool _owingOnly = false;
  bool _overdueOnly = false;
  int _page = 1;
  int _perPage = 20;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Any filter change starts again from the first page.
  void _filter(VoidCallback change) => setState(() {
    change();
    _page = 1;
  });

  AcademicYear? _selectedYear(List<AcademicYear> years) {
    if (years.isEmpty) return null;
    for (final year in years) {
      if (year.id == _yearId) return year;
    }
    for (final year in years) {
      if (year.isCurrent) return year;
    }
    return (List.of(years)..sort((a, b) => b.startDate.compareTo(a.startDate))).first;
  }

  @override
  Widget build(BuildContext context) {
    final studentId = widget.studentId;
    if (studentId != null) {
      final actor = ref.watch(authNotifierProvider).value;
      return StudentStatementView(
        studentId: studentId,
        academicYearId: _yearId,
        onBack: () => context.go('/student-fees'),
        // The matrix decides who takes money; a Super Admin only reads.
        canManage: actor != null && actor.role != UserRole.superAdmin && actor.canManage(AppModules.fees),
      );
    }

    final actor = ref.watch(authNotifierProvider).value;
    final mustPickSchool = actor?.picksSchool ?? false;
    final years = ref.watch(academicYearPickerProvider(_schoolId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Student Fees',
          actions: [
            SchoolFilterDropdown(
              selected: _schoolId,
              onChanged: (schoolId) => _filter(() {
                _schoolId = schoolId;
                _yearId = null;
                _classId = null;
              }),
            ),
          ],
        ),
        Expanded(
          child: mustPickSchool && _schoolId == null
              ? _Prompt(
                  message: actor?.role == UserRole.superAdmin
                      ? 'Choose a school to see its fees.'
                      : 'Choose a branch to see its fees.',
                )
              : AsyncValueView<List<AcademicYear>>(
                  value: years,
                  onRetry: () => ref.invalidate(academicYearPickerProvider(_schoolId)),
                  isEmpty: (years) => years.isEmpty,
                  emptyBuilder: (context) => const _Prompt(
                    message: 'Fees are charged per academic year, and there is none yet. Add one under Academic Years.',
                  ),
                  data: (context, years) => _body(years, _selectedYear(years)!),
                ),
        ),
      ],
    );
  }

  Widget _body(List<AcademicYear> years, AcademicYear year) {
    final query = (
      schoolId: _schoolId,
      academicYearId: year.id,
      schoolClassId: _classId,
      search: _searchText,
      owingOnly: _owingOnly,
      overdueOnly: _overdueOnly,
      page: _page,
      perPage: _perPage,
    );
    final classes = ref.watch(feeClassesProvider((schoolId: _schoolId, academicYearId: year.id))).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('year-$_schoolId'),
                  initialValue: year.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Academic year', isDense: true),
                  items: [for (final y in years) DropdownMenuItem(value: y.id, child: Text(y.name))],
                  onChanged: (id) => _filter(() {
                    _yearId = id;
                    _classId = null;
                  }),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('class-$_schoolId-${year.id}'),
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Class', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All classes')),
                    for (final schoolClass in (List.of(classes)..sort((a, b) => a.level.compareTo(b.level))))
                      DropdownMenuItem<int?>(value: schoolClass.id, child: Text(schoolClass.name)),
                  ],
                  onChanged: (id) => _filter(() => _classId = id),
                ),
              ),
              SizedBox(
                width: 260,
                child: DebouncedSearchField(
                  controller: _search,
                  label: 'Search name or admission no.',
                  onSearch: (text) => _filter(() => _searchText = text),
                ),
              ),
              FilterChip(
                label: const Text('Owing only'),
                selected: _owingOnly,
                onSelected: (value) => _filter(() => _owingOnly = value),
              ),
              FilterChip(
                label: const Text('Overdue only'),
                selected: _overdueOnly,
                onSelected: (value) => _filter(() => _overdueOnly = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncValueView<PaginatedResponse<StudentBalance>>(
            value: ref.watch(studentBalancesProvider(query)),
            onRetry: () => ref.invalidate(studentBalancesProvider(query)),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => _Prompt(
              message: _owingOnly || _overdueOnly || _searchText.isNotEmpty || _classId != null
                  ? 'No student matches these filters.'
                  : 'No student has been charged for ${year.name} yet. Fees are charged when they are published '
                        'under Fee Setup.',
            ),
            data: (context, page) => Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _BalanceRow(
                      row: page.items[index],
                      onOpen: () => context.go('/student-fees?student=${page.items[index].student.id}'),
                    ),
                  ),
                ),
                PaginationControls(
                  currentPage: page.currentPage,
                  lastPage: page.lastPage,
                  total: page.total,
                  perPage: page.perPage,
                  onPageChanged: (value) => setState(() => _page = value),
                  onPerPageChanged: (value) => _filter(() => _perPage = value),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.row, required this.onOpen});

  final StudentBalance row;
  final VoidCallback onOpen;

  String _money(String amount) => formatCurrency((centsOf(amount) ?? 0) / 100, row.currencyCode);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final overdue = (centsOf(row.overdue) ?? 0) > 0;
    final next = row.nextDueDate;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.student.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [
                      row.student.admissionNumber,
                      if (row.student.classLabel.isNotEmpty) row.student.classLabel,
                      if (next != null) 'next due ${formatDate(next)}',
                    ].join(' · '),
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ),
              Wrap(
                spacing: 18,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Figure(label: 'Charged', value: _money(row.charged)),
                  _Figure(label: 'Paid', value: _money(row.paid)),
                  _Figure(label: 'Balance', value: _money(row.balance), bold: true),
                  _Figure(label: 'Overdue', value: _money(row.overdue), color: overdue ? colors.danger : null),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.bold = false, this.color});

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(color: context.appColors.muted, fontSize: 12)),
        Text(
          value,
          style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color),
        ),
      ],
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.appColors.muted),
        ),
      ),
    );
  }
}
