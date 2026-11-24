import '../../../core/widgets/period_filter.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/errors/failure.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../../staff_leave/data/models/leave_status.dart';
import '../../staff_leave/data/models/leave_taken.dart';
import '../../staff_leave/data/models/leave_type.dart';
import '../../staff_leave/data/models/staff_leave.dart';
import '../application/my_leave_notifier.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../today/presentation/staff_words.dart';

/// "My leave" in the School365ai app (docs/teacher-app.md, T4): the person's
/// own requests, newest first, each with where it stands, and the way to ask
/// for more.
class MyLeaveScreen extends ConsumerWidget {
  const MyLeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leave = ref.watch(myLeaveProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('my-leave-apply'),
        onPressed: () => context.push('/leave/apply'),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.staffApplyForLeave),
      ),
      body: RefreshIndicator(
        key: const Key('my-leave-refresh'),
        onRefresh: () => ref.read(myLeaveProvider.notifier).refresh(),
        child: leave.hasValue
            ? _LeaveList(leave: leave.requireValue)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _Heading(),
                  const SizedBox(height: 12),
                  const _Period(),
                  const SizedBox(height: 16),
                  AsyncValueView<MyLeave>(
                    value: leave,
                    onRetry: () => ref.read(myLeaveProvider.notifier).retry(),
                    data: (context, value) => const SizedBox.shrink(),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.staffMyLeave,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _LeaveList extends ConsumerWidget {
  const _LeaveList({required this.leave});

  final MyLeave leave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final l10n = context.l10n;

    return ListView(
      key: const Key('my-leave-list'),
      // Room under the last card for the floating button.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const _Heading(),
        const SizedBox(height: 4),
        Text(l10n.staffMyLeaveSubtitle, style: TextStyle(color: colors.muted)),
        const SizedBox(height: 12),
        const _TakenCard(),
        const SizedBox(height: 12),
        const _Period(),
        const SizedBox(height: 16),
        if (leave.items.isEmpty)
          Padding(
            key: const Key('my-leave-empty'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.event_available_outlined, size: 48, color: colors.muted),
                const SizedBox(height: 12),
                Text(l10n.staffEmptyLeaveRequests(leave.period.name), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  l10n.staffApplyForLeaveHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted),
                ),
              ],
            ),
          )
        else ...[
          for (final item in leave.items) ...[_LeaveCard(leave: item), const SizedBox(height: 10)],
          if (leave.hasMore)
            Center(
              child: TextButton(
                key: const Key('my-leave-more'),
                onPressed: () => ref.read(myLeaveProvider.notifier).loadMore(),
                child: Text(l10n.staffShowOlderRequests),
              ),
            ),
        ],
      ],
    );
  }
}

class _LeaveCard extends ConsumerStatefulWidget {
  const _LeaveCard({required this.leave});

  final StaffLeave leave;

  @override
  ConsumerState<_LeaveCard> createState() => _LeaveCardState();
}

class _LeaveCardState extends ConsumerState<_LeaveCard> {
  /// Set while a withdrawal is on its way, so a second tap sends nothing.
  bool _withdrawing = false;

  StaffLeave get leave => widget.leave;

  Future<void> _withdraw() async {
    if (_withdrawing) return;

    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      title: l10n.staffWithdrawRequestQ,
      message: l10n.staffWithdrawRequestBody,
      confirmLabel: l10n.staffWithdraw,
      cancelLabel: l10n.staffKeepIt,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _withdrawing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(myLeaveProvider.notifier).withdraw(leave.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.staffLeaveWithdrawnDone)));
    } on Failure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(mounted ? failure.localizedMessage(context) : failure.message)));
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final start = formatIsoDate(leave.startDate);
    final end = formatIsoDate(leave.endDate);
    final dates = leave.startDate == leave.endDate ? start : l10n.staffDateRange(start, end);

    return Card(
      key: Key('my-leave-${leave.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    leaveTypeLabel(l10n, leave.leaveType),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusBadge(
                  label: leaveStatusLabel(l10n, leave.status),
                  tone: switch (leave.status) {
                    LeaveStatus.approved => BadgeTone.success,
                    LeaveStatus.rejected => BadgeTone.danger,
                    LeaveStatus.pending => BadgeTone.warning,
                    LeaveStatus.withdrawn => BadgeTone.neutral,
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              leave.leaveType == LeaveType.halfDay ? l10n.staffDatesHalfADay(dates) : dates,
              style: TextStyle(color: colors.muted),
            ),
            const SizedBox(height: 8),
            Text(leave.reason, style: const TextStyle(height: 1.35)),
            if (leave.reviewRemarks != null && leave.reviewRemarks!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${leave.reviewedByName ?? l10n.staffReviewer}: ${leave.reviewRemarks}',
                style: TextStyle(fontSize: 13, color: colors.muted, fontStyle: FontStyle.italic),
              ),
            ],
            // Only while nobody has decided it: an approved request is the
            // office's to undo (docs/mobile-apps-review.md, 1.9).
            if (leave.status == LeaveStatus.pending)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: Key('my-leave-withdraw-${leave.id}'),
                  onPressed: _withdrawing ? null : _withdraw,
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(_withdrawing ? l10n.staffWithdrawing : l10n.staffWithdraw),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What was taken this year, by kind, in working days.
class _TakenCard extends ConsumerWidget {
  const _TakenCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taken = ref.watch(myLeaveTakenProvider);
    final colors = context.appColors;

    return Card(
      key: const Key('my-leave-taken'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: taken.when(
          loading: () => const SizedBox(height: 48, child: Center(child: CircularProgressIndicator())),
          error: (error, _) => Row(
            children: [
              Expanded(
                child: Text(context.l10n.staffLeaveTakenLoadFailed, style: TextStyle(color: colors.muted)),
              ),
              TextButton(
                key: const Key('my-leave-taken-retry'),
                onPressed: () => ref.invalidate(myLeaveTakenProvider),
                child: Text(context.l10n.retry),
              ),
            ],
          ),
          data: (value) => _TakenFigures(taken: value),
        ),
      ),
    );
  }
}

class _TakenFigures extends StatelessWidget {
  const _TakenFigures({required this.taken});

  final LeaveTaken taken;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final kinds = [
      for (final entry in taken.days.entries)
        if (entry.value > 0) entry,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.staffTakenIn(taken.label), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          dayCount(taken.totalDays, l10n),
          key: const Key('my-leave-taken-total'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (kinds.isEmpty)
          Text(l10n.staffNoLeaveTakenYet, style: TextStyle(color: colors.muted))
        else
          Text(
            [for (final kind in kinds) '${leaveTypeLabel(l10n, kind.key)} ${dayCount(kind.value, l10n)}'].join(' · '),
            style: TextStyle(color: colors.muted),
          ),
        if (taken.pendingRequests > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l10n.staffRequestsWaiting(taken.pendingRequests), style: TextStyle(color: colors.muted)),
          ),
      ],
    );
  }
}

/// "1 day", "2.5 days", "0 days" - working days, halves where a half day was taken.
/// English unless [l10n] is given.
String dayCount(double days, [AppLocalizations? l10n]) {
  final words = l10n ?? AppLocalizationsEn();
  final number = days == days.roundToDouble() ? days.toStringAsFixed(0) : days.toString();

  return days == 1 ? words.staffOneDay : words.staffDays(number);
}

/// All / Today / This week / This month - leave that touches the period.
class _Period extends ConsumerWidget {
  const _Period();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(myLeaveProvider);
    final notifier = ref.read(myLeaveProvider.notifier);

    return PeriodFilter(value: notifier.period, onChanged: notifier.setPeriod);
  }
}
