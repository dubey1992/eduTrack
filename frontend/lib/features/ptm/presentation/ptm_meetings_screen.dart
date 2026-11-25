import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/ptm_providers.dart';
import '../data/ptm_models.dart';
import 'ptm_meeting_dialog.dart';

/// The school's admins and the meeting's class teachers both open this.
bool _isOffice(UserRole? role) =>
    role == UserRole.superAdmin || role == UserRole.groupAdmin || role == UserRole.schoolAdmin;

/// Parent-teacher meetings (docs/mobile-apps-review.md, M12, 8.4): the office
/// creates the day and picks the classes; each class teacher opens times for
/// their class; parents book from the Family app.
class PtmMeetingsScreen extends ConsumerWidget {
  const PtmMeetingsScreen({super.key, this.compact = false});

  /// The Staff app's own screen: its app bar has the title.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final past = ref.watch(ptmShowPastProvider);
    final meetings = ref.watch(ptmMeetingsProvider);
    final office = _isOffice(ref.watch(authNotifierProvider).value?.role);

    final filter = SegmentedButton<bool>(
      key: const Key('ptm-filter'),
      segments: [
        ButtonSegment(value: false, label: Text(l10n.ptmAhead)),
        ButtonSegment(value: true, label: Text(l10n.ptmPast)),
      ],
      selected: {past},
      onSelectionChanged: (choice) => ref.read(ptmShowPastProvider.notifier).show(past: choice.first),
    );
    final create = FilledButton.icon(
      key: const Key('ptm-new'),
      onPressed: () => showDialog<void>(context: context, builder: (_) => const PtmMeetingDialog()),
      icon: const Icon(Icons.add_rounded),
      label: Text(l10n.ptmNewMeeting),
    );

    return ListView(
      padding: EdgeInsets.only(top: compact ? 12 : 0, bottom: 24),
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Wrap(spacing: 12, runSpacing: 8, children: [filter, if (office) create]),
          )
        else
          SectionHeader(title: l10n.ptmMeetings, actions: [filter, if (office) create]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            office ? l10n.ptmIntroOffice : l10n.ptmIntroTeacher,
            style: TextStyle(color: context.appColors.muted),
          ),
        ),
        const SizedBox(height: 12),
        AsyncValueView(
          value: meetings,
          onRetry: () => ref.read(ptmMeetingsProvider.notifier).refresh(),
          isEmpty: (page) => page.items.isEmpty,
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                past ? l10n.ptmNoPastMeetings : l10n.ptmNoMeetingsAhead,
                style: TextStyle(color: context.appColors.muted),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (context, page) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (final meeting in page.items) ...[
                  _MeetingCard(meeting: meeting, office: office, past: past),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MeetingCard extends ConsumerWidget {
  const _MeetingCard({required this.meeting, required this.office, required this.past});

  final PtmMeeting meeting;
  final bool office;
  final bool past;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ptmCancelMeetingQ(meeting.title)),
        content: Text(l10n.ptmCancelMeetingBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.ptmKeepMeeting)),
          FilledButton(
            key: const Key('ptm-cancel-confirm'),
            style: FilledButton.styleFrom(backgroundColor: context.appColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.ptmCancelMeeting),
          ),
        ],
      ),
    );
    if (yes != true) return;

    try {
      await ref.read(ptmMeetingsProvider.notifier).cancelMeeting(meeting.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.ptmMeetingCancelled)));
    } on Failure catch (failure) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colours = context.appColors;
    final editable = office && !past && !meeting.cancelled;

    return Card(
      key: Key('ptm-meeting-${meeting.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(meeting.title, style: Theme.of(context).textTheme.titleMedium),
                Text(formatDate(meeting.date), style: TextStyle(color: colours.muted)),
                if (meeting.cancelled)
                  StatusBadge(label: l10n.ptmCancelled, tone: BadgeTone.danger)
                else if (!past && !meeting.bookingOpen)
                  StatusBadge(label: l10n.ptmBookingClosed, tone: BadgeTone.warning),
              ],
            ),
            if (meeting.note != null) ...[const SizedBox(height: 4), Text(meeting.note!)],
            const SizedBox(height: 8),
            for (final row in meeting.classes)
              ListTile(
                key: Key('ptm-class-${meeting.id}-${row.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.groups_2_outlined),
                title: Text(row.name),
                subtitle: Text(
                  [
                    row.classTeacher ?? l10n.ptmNoClassTeacher,
                    row.slots == 0 ? l10n.ptmNoTimesYet : l10n.ptmBookedOf(row.booked, row.slots),
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/meetings/${meeting.id}/classes/${row.id}'),
              ),
            if (editable)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: Key('ptm-edit-${meeting.id}'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => PtmMeetingDialog(meeting: meeting),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l10n.ptmEdit),
                  ),
                  TextButton.icon(
                    key: Key('ptm-cancel-${meeting.id}'),
                    onPressed: () => _cancel(context, ref),
                    icon: Icon(Icons.event_busy_outlined, size: 18, color: colours.danger),
                    label: Text(l10n.ptmCancelMeeting, style: TextStyle(color: colours.danger)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
