import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../call_requests/call_requests.dart' show diallerProvider;
import '../application/ptm_providers.dart';
import '../data/ptm_models.dart';

/// The slot lengths a teacher picks from, in minutes (5 to 60, server rule).
const ptmSlotLengths = [5, 10, 15, 20, 30, 45, 60];

/// One class's times in one meeting: open more, see who booked, call them,
/// and remove a time (a booked one tells the parent).
class PtmSlotsScreen extends ConsumerWidget {
  const PtmSlotsScreen({super.key, required this.meetingId, required this.sectionId});

  final int meetingId;
  final int sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final meeting = ref.watch(ptmMeetingProvider(meetingId));
    final key = (meetingId, sectionId);
    final slots = ref.watch(ptmSlotsProvider(key));

    return AsyncValueView<PtmMeeting>(
      value: meeting,
      onRetry: () => ref.invalidate(ptmMeetingProvider(meetingId)),
      data: (context, meeting) {
        final today = DateUtils.dateOnly(DateTime.now());
        final ahead = !meeting.cancelled && !meeting.date.isBefore(today);
        final className = meeting.classes.where((c) => c.id == sectionId).map((c) => c.name).firstOrNull;

        return ListView(
          key: const Key('ptm-slots'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text([?className, meeting.title].join(' · '), style: Theme.of(context).textTheme.titleLarge),
            Text(formatDate(meeting.date), style: TextStyle(color: context.appColors.muted)),
            if (meeting.cancelled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.ptmMeetingWasCancelled, style: TextStyle(color: context.appColors.danger)),
              ),
            const SizedBox(height: 16),
            if (ahead) ...[_OpenTimesCard(slotsKey: key), const SizedBox(height: 16)],
            AsyncValueView<List<PtmSlot>>(
              value: slots,
              onRetry: () => ref.read(ptmSlotsProvider(key).notifier).refresh(),
              isEmpty: (rows) => rows.isEmpty,
              emptyBuilder: (context) => Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(l10n.ptmNoTimesOpened, style: TextStyle(color: context.appColors.muted)),
                ),
              ),
              data: (context, rows) {
                final booked = rows.where((s) => s.booking != null).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.ptmBookedOf(booked, rows.length), style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (final slot in rows) _SlotTile(slot: slot, slotsKey: key, editable: ahead),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _OpenTimesCard extends ConsumerStatefulWidget {
  const _OpenTimesCard({required this.slotsKey});

  final (int, int) slotsKey;

  @override
  ConsumerState<_OpenTimesCard> createState() => _OpenTimesCardState();
}

class _OpenTimesCardState extends ConsumerState<_OpenTimesCard> {
  TimeOfDay _from = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 12, minute: 0);
  int _minutes = 10;
  bool _saving = false;
  String? _error;

  static String _wire(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _pick({required bool from}) async {
    final picked = await showTimePicker(context: context, initialTime: from ? _from : _to);
    if (picked == null) return;
    setState(() => from ? _from = picked : _to = picked);
  }

  Future<void> _open() async {
    if (_saving) return;
    final l10n = context.l10n;
    if (_to.hour * 60 + _to.minute <= _from.hour * 60 + _from.minute) {
      setState(() => _error = l10n.ptmEndAfterStart);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      final added = await ref
          .read(ptmSlotsProvider(widget.slotsKey).notifier)
          .open(startsAt: _wire(_from), endsAt: _wire(_to), minutes: _minutes);
      messenger.showSnackBar(SnackBar(content: Text(added == 0 ? l10n.ptmNoNewTimes : l10n.ptmTimesOpened(added))));
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.localizedMessage(context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.ptmOpenTimes, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.ptmOpenTimesHelp, style: TextStyle(color: context.appColors.muted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('ptm-from'),
                  onPressed: () => _pick(from: true),
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(l10n.ptmFromTime(formatClock(_wire(_from)))),
                ),
                OutlinedButton.icon(
                  key: const Key('ptm-to'),
                  onPressed: () => _pick(from: false),
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(l10n.ptmToTime(formatClock(_wire(_to)))),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int>(
                    key: const Key('ptm-length'),
                    isExpanded: true,
                    initialValue: _minutes,
                    decoration: InputDecoration(labelText: l10n.ptmSlotLength),
                    items: [
                      for (final m in ptmSlotLengths) DropdownMenuItem(value: m, child: Text(l10n.ptmMinutes(m))),
                    ],
                    onChanged: (value) => setState(() => _minutes = value ?? _minutes),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('ptm-open-error'),
                style: TextStyle(color: context.appColors.danger),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('ptm-open'),
              onPressed: _saving ? null : _open,
              child: Text(l10n.ptmOpenTimesButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends ConsumerWidget {
  const _SlotTile({required this.slot, required this.slotsKey, required this.editable});

  final PtmSlot slot;
  final (int, int) slotsKey;
  final bool editable;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final booking = slot.booking;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ptmRemoveTimeQ(formatClock(slot.startsAt))),
        content: Text(booking == null ? l10n.ptmRemoveFreeBody : l10n.ptmRemoveBookedBody(booking.parentName)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            key: const Key('ptm-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.ptmRemove),
          ),
        ],
      ),
    );
    if (yes != true) return;

    try {
      await ref.read(ptmSlotsProvider(slotsKey).notifier).remove(slot.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.ptmTimeRemoved)));
    } on Failure catch (failure) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final booking = slot.booking;
    final mobile = booking?.parentMobile;

    return Card(
      key: Key('ptm-slot-${slot.id}'),
      child: ListTile(
        leading: Icon(
          booking == null ? Icons.event_available_outlined : Icons.person_rounded,
          color: booking == null ? context.appColors.muted : context.appColors.success,
        ),
        title: Text('${formatClock(slot.startsAt)} - ${formatClock(slot.endsAt)}'),
        subtitle: Text(booking == null ? l10n.ptmFree : l10n.ptmBookedBy(booking.studentName, booking.parentName)),
        trailing: Wrap(
          children: [
            if (mobile != null)
              IconButton(
                key: Key('ptm-dial-${slot.id}'),
                tooltip: l10n.ptmCallParent(mobile),
                onPressed: () => ref.read(diallerProvider)(Uri(scheme: 'tel', path: mobile.replaceAll(' ', ''))),
                icon: const Icon(Icons.call_rounded),
              ),
            if (editable)
              IconButton(
                key: Key('ptm-remove-${slot.id}'),
                tooltip: l10n.ptmRemoveTime,
                onPressed: () => _remove(context, ref),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
