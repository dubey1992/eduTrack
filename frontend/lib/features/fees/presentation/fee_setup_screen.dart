import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../academic_years/application/academic_year_picker_provider.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../../auth/application/auth_notifier.dart';
import 'widgets/fee_heads_tab.dart';
import 'widgets/fee_structures_tab.dart';

/// Fee Setup (docs/fees.md, F1): the kinds of fee a school charges, and
/// what each class and each bus route pays for an academic year, split into
/// installments. Publishing a fee is what will charge students, from step
/// F2 on.
class FeeSetupScreen extends ConsumerStatefulWidget {
  const FeeSetupScreen({super.key});

  @override
  ConsumerState<FeeSetupScreen> createState() => _FeeSetupScreenState();
}

class _FeeSetupScreenState extends ConsumerState<FeeSetupScreen> {
  /// The school chosen by a Super Admin or a Group Admin; null for anyone
  /// whose school the server already knows.
  int? _schoolId;

  /// The year being looked at. Null until the years have loaded, then the
  /// current one.
  int? _yearId;

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    // The matrix decides who changes fees, so a school can let its front
    // desk do it. A Super Admin only reads: fees are the school's business.
    final canManage = actor != null && actor.role != UserRole.superAdmin && actor.canManage(AppModules.fees);
    final mustPickSchool = actor?.picksSchool ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Fee Setup',
          actions: [
            SchoolFilterDropdown(
              selected: _schoolId,
              onChanged: (schoolId) => setState(() {
                _schoolId = schoolId;
                _yearId = null;
              }),
            ),
            if (!mustPickSchool || _schoolId != null) _yearPicker(),
          ],
        ),
        if (!canManage && actor != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('View only - fees are set up by the school.', style: TextStyle(color: context.appColors.muted)),
          ),
        Expanded(
          child: mustPickSchool && _schoolId == null
              // A Super Admin chooses between schools, anyone else between
              // the branches of their group - the dropdown says the same.
              ? _Prompt(
                  message: actor?.role == UserRole.superAdmin
                      ? 'Choose a school to see its fees.'
                      : 'Choose a branch to see its fees.',
                )
              : _tabs(canManage),
        ),
      ],
    );
  }

  Widget _yearPicker() {
    final years = ref.watch(academicYearPickerProvider(_schoolId));

    return years.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
      data: (years) {
        final selected = _selectedYear(years);
        if (selected == null) return const SizedBox.shrink();

        return SizedBox(
          width: 200,
          child: DropdownButtonFormField<int>(
            // A new school is a new list of years; start it afresh.
            key: ValueKey(_schoolId),
            initialValue: selected.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Academic year', isDense: true),
            items: [for (final year in years) DropdownMenuItem(value: year.id, child: Text(year.name))],
            onChanged: (id) => setState(() => _yearId = id),
          ),
        );
      },
    );
  }

  /// The year chosen, or the current one, or the latest one.
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

  /// The tabs are always there. Fee types belong to the school, not to a
  /// year, so that tab works before any academic year exists; the two fee
  /// tabs need a year, and say so when there is none.
  Widget _tabs(bool canManage) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Fee Types'),
              Tab(text: 'Class Fees'),
              Tab(text: 'Bus Route Fees'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                FeeHeadsTab(schoolId: _schoolId, canManage: canManage),
                _forYear(
                  (year) => FeeStructuresTab(
                    kind: FeeStructureKind.classFee,
                    schoolId: _schoolId,
                    year: year,
                    canManage: canManage,
                  ),
                ),
                _forYear(
                  (year) => FeeStructuresTab(
                    kind: FeeStructureKind.routeFee,
                    schoolId: _schoolId,
                    year: year,
                    canManage: canManage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [build] for the chosen academic year, or the reason there is none.
  Widget _forYear(Widget Function(AcademicYear year) build) {
    return AsyncValueView<List<AcademicYear>>(
      value: ref.watch(academicYearPickerProvider(_schoolId)),
      onRetry: () => ref.invalidate(academicYearPickerProvider(_schoolId)),
      isEmpty: (years) => years.isEmpty,
      emptyBuilder: (context) => const _Prompt(
        message: 'Fees are set per academic year, and there is none yet. Add one under Academic Years first.',
      ),
      data: (context, years) => build(_selectedYear(years)!),
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
