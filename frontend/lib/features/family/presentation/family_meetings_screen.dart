import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../application/family_meetings_notifier.dart';
import '../application/family_session_notifier.dart';
import '../data/models/family_account.dart';
import '../data/models/family_meeting.dart';
import 'widgets/family_widgets.dart';

/// Parent-teacher meetings for the chosen child (docs/mobile-apps-review.md,
/// M12, 8.4): pick a free time with the class teacher, move it, or cancel it
/// until the end of the day before.
class FamilyMeetingsScreen extends ConsumerWidget {
  const FamilyMeetingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(selectedChildProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.familyMeetings),
            if (child != null) Text(child.fullName, style: TextStyle(fontSize: 12, color: context.appColors.muted)),
          ],
        ),
      ),
      body: child == null
          ? FamilyEmptyView(icon: Icons.family_restroom_rounded, title: l10n.familyNoChildrenTitle)
          : ref
                .watch(familyMeetingsProvider(child.id))
                .when(
                  loading: () => const PlaceholderCards(),
                  error: (error, _) => FamilyErrorView(
                    error: error,
                    onRetry: () => ref.read(familyMeetingsProvider(child.id).notifier).refresh(),
                  ),
                  data: (meetings) => meetings.isEmpty
                      ? FamilyEmptyView(
                          icon: Icons.groups_2_rounded,
                          title: l10n.familyNoMeetings,
                          message: l10n.familyNoMeetingsMessage,
                        )
                      : RefreshIndicator(
                          onRefresh: () => ref.read(familyMeetingsProvider(child.id).notifier).refresh(),
                          child: ListView.separated(
                            key: const Key('family-meetings'),
                            padding: const EdgeInsets.all(16),
                            itemCount: meetings.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) => _MeetingCard(child: child, meeting: meetings[index]),
                          ),
                        ),
                ),
    );
  }
}

class _MeetingCard extends ConsumerStatefulWidget {
  const _MeetingCard({required this.child, required this.meeting});

  final FamilyChild child;
  final FamilyMeeting meeting;

  @override
  ConsumerState<_MeetingCard> createState() => _MeetingCardState();
}

class _MeetingCardState extends ConsumerState<_MeetingCard> {
  bool _busy = false;

  FamilyMeeting get _meeting => widget.meeting;

  String _teacher(BuildContext context) => _meeting.teacherName ?? context.l10n.familyTheClassTeacherLower;

  Future<void> _run(Future<void> Function() change, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await change();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on Failure catch (failure) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(FamilyMeetingSlot slot) async {
    final l10n = context.l10n;
    final time = formatClock(slot.startsAt);
    final moving = _meeting.mySlot != null;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(moving ? l10n.familyMoveTimeQ(time) : l10n.familyBookTimeQ(time)),
        content: Text(l10n.familyBookTimeBody(_meeting.dateLabel, _teacher(context), widget.child.firstName)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            key: const Key('family-meeting-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(moving ? l10n.familyMove : l10n.familyBook),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    await _run(
      () => ref.read(familyMeetingsProvider(widget.child.id).notifier).book(_meeting.id, slot.id),
      l10n.familyBookedFor(time),
    );
  }

  Future<void> _cancel() async {
    final l10n = context.l10n;
    final mine = _meeting.mySlot!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.familyCancelBookingQ),
        content: Text(l10n.familyCancelBookingBody(formatClock(mine.startsAt))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.familyKeepIt)),
          FilledButton(
            key: const Key('family-meeting-cancel-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.familyCancelBooking),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    await _run(
      () => ref.read(familyMeetingsProvider(widget.child.id).notifier).cancel(_meeting.id),
      l10n.familyBookingCancelled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colours = context.appColors;
    final mine = _meeting.mySlot;
    final open = _meeting.bookingOpen;

    return FamilyCard(
      key: Key('family-meeting-${_meeting.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_meeting.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(l10n.familyMeetingWith(_meeting.dateLabel, _teacher(context)), style: TextStyle(color: colours.muted)),
          if (_meeting.note != null) ...[const SizedBox(height: 8), Text(_meeting.note!)],
          const SizedBox(height: 12),
          if (mine != null)
            Container(
              key: const Key('family-meeting-mine'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colours.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_available_rounded, color: colours.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.familyYourTime('${formatClock(mine.startsAt)} - ${formatClock(mine.endsAt)}'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (!open)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.familyMeetingClosed, style: TextStyle(color: colours.muted)),
            )
          else if (_meeting.slots.isEmpty)
            Text(l10n.familyMeetingTimesNotOpen, style: TextStyle(color: colours.muted))
          else ...[
            if (mine == null && !_meeting.hasFreeSlot)
              Text(l10n.familyMeetingAllTaken, style: TextStyle(color: colours.muted))
            else
              Padding(
                padding: EdgeInsets.only(top: mine == null ? 0 : 12, bottom: 8),
                child: Text(
                  mine == null ? l10n.familyPickATime : l10n.familyPickAnotherTime,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final slot in _meeting.slots) _SlotChip(slot: slot, onPick: _busy ? null : _pick)],
            ),
            if (mine != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('family-meeting-cancel'),
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.event_busy_rounded),
                  label: Text(l10n.familyCancelBooking),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.onPick});

  final FamilyMeetingSlot slot;
  final void Function(FamilyMeetingSlot slot)? onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final time = formatClock(slot.startsAt);
    final label = slot.mine
        ? l10n.familySlotYoursLabel(time)
        : slot.free
        ? time
        : l10n.familySlotTakenLabel(time);

    return Semantics(
      label: label,
      excludeSemantics: true,
      button: slot.free,
      selected: slot.mine,
      child: ChoiceChip(
        key: Key('family-meeting-slot-${slot.id}'),
        label: Text(
          time,
          style: slot.free || slot.mine ? null : const TextStyle(decoration: TextDecoration.lineThrough),
        ),
        selected: slot.mine,
        onSelected: slot.free && onPick != null ? (_) => onPick!(slot) : null,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
