import 'package:flutter/material.dart';

import '../../../transport/data/models/transport_trip.dart';

/// "Board everyone at this stop" (docs/mobile-apps-review.md, 1.1): every
/// child the mark applies to, all ticked; the crew unticks the few who are
/// not there and confirms. Forty children are one tap and an exception or
/// two, not forty taps.
///
/// Returns the children to mark, or null when the crew backed out.
Future<List<TripRider>?> showBulkMarkSheet(
  BuildContext context, {
  required List<TripRider> riders,
  required TripRiderStatus to,
  required String where,
}) {
  return showModalBottomSheet<List<TripRider>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _BulkMarkSheet(riders: riders, to: to, where: where),
  );
}

/// "Board" / "Drop" - the verb on the sheet's button.
String bulkVerb(TripRiderStatus to) => to == TripRiderStatus.dropped ? 'Drop' : 'Board';

class _BulkMarkSheet extends StatefulWidget {
  const _BulkMarkSheet({required this.riders, required this.to, required this.where});

  final List<TripRider> riders;
  final TripRiderStatus to;
  final String where;

  @override
  State<_BulkMarkSheet> createState() => _BulkMarkSheetState();
}

class _BulkMarkSheetState extends State<_BulkMarkSheet> {
  late final Set<int> _ticked = {for (final rider in widget.riders) rider.studentId};

  @override
  Widget build(BuildContext context) {
    final verb = bulkVerb(widget.to);
    final chosen = [
      for (final rider in widget.riders)
        if (_ticked.contains(rider.studentId)) rider,
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          key: const Key('bulk-mark-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('$verb at ${widget.where}', style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Untick anyone who is not here.', style: Theme.of(context).textTheme.bodyMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final rider in widget.riders)
                    CheckboxListTile(
                      key: Key('bulk-mark-${rider.studentId}'),
                      value: _ticked.contains(rider.studentId),
                      onChanged: (on) => setState(() {
                        if (on == true) {
                          _ticked.add(rider.studentId);
                        } else {
                          _ticked.remove(rider.studentId);
                        }
                      }),
                      title: Text(rider.name),
                      subtitle: rider.classSectionName == null ? null : Text(rider.classSectionName!),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 56,
                child: FilledButton(
                  key: const Key('bulk-mark-confirm'),
                  onPressed: chosen.isEmpty ? null : () => Navigator.of(context).pop(chosen),
                  child: Text('$verb ${chosen.length}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
