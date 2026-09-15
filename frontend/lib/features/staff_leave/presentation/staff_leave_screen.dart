import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/staff_leave_list_notifier.dart';
import '../application/staff_leave_summary_notifier.dart';
import '../data/models/leave_status.dart';
import '../data/models/staff_leave.dart';
import '../data/models/staff_leave_summary.dart';
import 'apply_leave_dialog.dart';

/// Phase 9 - staff leave requests and their review, tightly coupled to
/// Phase 8's staff attendance register: approving a request marks every
/// date in its range as "Leave" there (see StaffLeaveService::approve on
/// the backend), so the two never silently disagree.
class StaffLeaveScreen extends ConsumerStatefulWidget {
  const StaffLeaveScreen({super.key});

  @override
  ConsumerState<StaffLeaveScreen> createState() => _StaffLeaveScreenState();
}

class _StaffLeaveScreenState extends ConsumerState<StaffLeaveScreen> {
  int? _schoolFilter;
  String? _statusFilter;

  static const _reviewerRoles = {UserRole.hod, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.superAdmin};
  // A school admin both applies for their own leave (they get a minimal
  // auto-created StaffProfile for exactly this - see UserService::create()
  // on the backend) and reviews everyone else's - self-review is blocked
  // server-side, not by hiding either ability here.
  static const _applicantRoles = {
    UserRole.teacher,
    UserRole.staff,
    UserRole.hod,
    UserRole.transportManager,
    UserRole.schoolAdmin,
  };

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authNotifierProvider).value?.role;
    final canApply = role != null && _applicantRoles.contains(role);
    final canReview = role != null && _reviewerRoles.contains(role);
    final leavesState = ref.watch(staffLeaveListNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Staff Leave',
          actions: [
            if (canApply)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const ApplyLeaveDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Apply Leave'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(staffLeaveListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        const _SummaryRow(),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _statusFilter == null,
                onSelected: (_) => _setStatusFilter(null),
              ),
              for (final status in LeaveStatus.values)
                ChoiceChip(
                  label: Text(status.label),
                  selected: _statusFilter == status.apiValue,
                  onSelected: (_) => _setStatusFilter(status.apiValue),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AsyncValueView<PagedList<StaffLeave>>(
            value: leavesState,
            onRetry: () => ref.read(staffLeaveListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No leave requests found.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _LeaveListMobile(leaves: page.items, canReview: canReview),
                      desktop: (context) => _LeaveListDesktop(leaves: page.items, canReview: canReview),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(staffLeaveListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(staffLeaveListNotifierProvider.notifier).setPerPage(p),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _setStatusFilter(String? status) {
    setState(() => _statusFilter = status);
    ref.read(staffLeaveListNotifierProvider.notifier).setStatusFilter(status);
  }
}

class _SummaryRow extends ConsumerWidget {
  const _SummaryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryState = ref.watch(staffLeaveSummaryNotifierProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AsyncValueView<StaffLeaveSummary>(
        value: summaryState,
        data: (context, summary) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              KpiCard(label: 'Pending', value: '${summary.pending}'),
              KpiCard(label: 'Approved This Month', value: '${summary.approvedThisMonth}'),
              KpiCard(label: 'Rejected', value: '${summary.rejected}'),
              KpiCard(label: 'On Leave Today', value: '${summary.onLeaveToday}'),
            ],
          );
        },
      ),
    );
  }
}

class _LeaveStatusBadge extends StatelessWidget {
  const _LeaveStatusBadge({required this.status});

  final LeaveStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      LeaveStatus.pending => BadgeTone.warning,
      LeaveStatus.approved => BadgeTone.success,
      LeaveStatus.rejected => BadgeTone.danger,
    };

    return StatusBadge(label: status.label, tone: tone);
  }
}

Future<void> _review(BuildContext context, WidgetRef ref, {required StaffLeave leave, required bool approve}) async {
  try {
    if (approve) {
      await ref.read(staffLeaveListNotifierProvider.notifier).approve(leave);
    } else {
      await ref.read(staffLeaveListNotifierProvider.notifier).reject(leave);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(approve ? 'Leave request approved.' : 'Leave request rejected.')));
    }
  } catch (error) {
    final failure = error is Failure ? error : Failure.unknown(error.toString());
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

class _LeaveListMobile extends ConsumerWidget {
  const _LeaveListMobile({required this.leaves, required this.canReview});

  final List<StaffLeave> leaves;
  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: leaves.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final leave = leaves[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        leave.staffName ?? 'Staff #${leave.staffProfileId}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    _LeaveStatusBadge(status: leave.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${leave.leaveType.label} · ${leave.startDate} to ${leave.endDate}'),
                if (leave.departmentName != null) Text(leave.departmentName!),
                Text(leave.reason),
                if (canReview && leave.status == LeaveStatus.pending) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _review(context, ref, leave: leave, approve: false),
                        child: const Text('Reject'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _review(context, ref, leave: leave, approve: true),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LeaveListDesktop extends ConsumerWidget {
  const _LeaveListDesktop({required this.leaves, required this.canReview});

  final List<StaffLeave> leaves;
  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Staff')),
              DataColumn(label: Text('Department')),
              DataColumn(label: Text('Leave Type')),
              DataColumn(label: Text('From')),
              DataColumn(label: Text('To')),
              DataColumn(label: Text('Reason')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final leave in leaves)
                DataRow(
                  cells: [
                    DataCell(Text(leave.staffName ?? 'Staff #${leave.staffProfileId}')),
                    DataCell(Text(leave.departmentName ?? '—')),
                    DataCell(Text(leave.leaveType.label)),
                    DataCell(Text(leave.startDate)),
                    DataCell(Text(leave.endDate)),
                    DataCell(SizedBox(width: 220, child: Text(leave.reason, overflow: TextOverflow.ellipsis))),
                    DataCell(_LeaveStatusBadge(status: leave.status)),
                    DataCell(
                      canReview && leave.status == LeaveStatus.pending
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () => _review(context, ref, leave: leave, approve: true),
                                  child: const Text('Approve'),
                                ),
                                TextButton(
                                  onPressed: () => _review(context, ref, leave: leave, approve: false),
                                  child: const Text('Reject'),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
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
