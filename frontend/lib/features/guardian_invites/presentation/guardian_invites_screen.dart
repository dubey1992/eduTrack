import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/section_header.dart';
import '../application/guardian_invites_notifier.dart';
import '../data/guardian_invites.dart';

/// Parents asking the school to add another guardian of their child
/// (docs/mobile-apps-review.md, M8, 8.5). Waiting requests first; Approve
/// links the guardian as adding one by hand does, after which the set-up
/// code goes out from the student's Guardians.
class GuardianInvitesScreen extends ConsumerWidget {
  const GuardianInvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(guardianInvitesFilterProvider);
    final invites = ref.watch(guardianInvitesProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        SectionHeader(
          title: 'Guardian Requests',
          actions: [
            SegmentedButton<GuardianInviteStatus>(
              key: const Key('guardian-invites-filter'),
              segments: [
                for (final status in GuardianInviteStatus.values)
                  ButtonSegment(value: status, label: Text(status.label)),
              ],
              selected: {filter.status},
              onSelectionChanged: (choice) => ref.read(guardianInvitesFilterProvider.notifier).show(choice.first),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            "Parents ask here for another guardian - often the other parent - to use the Family app. Nobody sees a "
            "child's records until you approve. Once approved, give them their set-up code from the student's "
            'Guardians.',
            style: TextStyle(color: context.appColors.muted),
          ),
        ),
        const SizedBox(height: 12),
        AsyncValueView(
          value: invites,
          onRetry: () => ref.invalidate(guardianInvitesProvider),
          isEmpty: (page) => page.items.isEmpty,
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                filter.status == GuardianInviteStatus.pending
                    ? 'No requests waiting.'
                    : 'No ${filter.status.label.toLowerCase()} requests.',
                style: TextStyle(color: context.appColors.muted),
              ),
            ),
          ),
          data: (context, page) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (final invite in page.items) ...[_InviteCard(invite: invite), const SizedBox(height: 10)],
                if (page.lastPage > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Page ${page.currentPage} of ${page.lastPage}'),
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: page.currentPage > 1
                            ? () => ref.read(guardianInvitesFilterProvider.notifier).goTo(page.currentPage - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: page.currentPage < page.lastPage
                            ? () => ref.read(guardianInvitesFilterProvider.notifier).goTo(page.currentPage + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({required this.invite});

  final GuardianInvite invite;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    if (_busy) return;
    final invite = widget.invite;

    final confirmed = await confirmDialog(
      context,
      title: approve ? 'Approve ${invite.name}?' : 'Decline this request?',
      message: approve
          ? '${invite.name} becomes a guardian of ${invite.studentName}, with the same rights as any guardian. '
                "Give them their set-up code from the student's Guardians."
          : '${invite.name} will not be added. ${invite.requestedByName} sees that the school declined.',
      confirmLabel: approve ? 'Approve' : 'Decline',
      isDestructive: !approve,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(guardianInvitesRepositoryProvider);
      await (approve ? repository.approve(invite.id) : repository.decline(invite.id));
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? '${invite.name} added as a guardian.' : 'Request declined.')),
      );
      ref.invalidate(guardianInvitesProvider);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final muted = context.appColors.muted;
    final waiting = invite.status == GuardianInviteStatus.pending;

    return Card(
      key: Key('guardian-invite-${invite.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${invite.name} · ${_relationship(invite.relationship)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(invite.mobile, style: TextStyle(color: muted)),
                  const SizedBox(height: 6),
                  Text('For ${invite.studentName} (${[invite.admissionNumber, ?invite.classSectionName].join(' · ')})'),
                  Text(
                    [
                      'Asked by ${invite.requestedByName}',
                      if (invite.askedAt != null) formatDate(invite.askedAt!),
                      if (!waiting && invite.decidedByName != null)
                        '${invite.status.label.toLowerCase()} by ${invite.decidedByName}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ],
              ),
            ),
            if (waiting) ...[
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: Key('guardian-invite-decline-${invite.id}'),
                    onPressed: _busy ? null : () => _decide(approve: false),
                    child: const Text('Decline'),
                  ),
                  FilledButton(
                    key: Key('guardian-invite-approve-${invite.id}'),
                    onPressed: _busy ? null : () => _decide(approve: true),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _relationship(String value) => switch (value) {
    'mother' => 'Mother',
    'father' => 'Father',
    'guardian' => 'Guardian',
    _ => 'Other',
  };
}
