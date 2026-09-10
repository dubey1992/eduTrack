import 'package:flutter/material.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../data/models/transport_status.dart';

/// Shared bits of the three transport list screens.
class TransportStatusBadge extends StatelessWidget {
  const TransportStatusBadge({super.key, required this.status});

  final TransportStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status.label,
      tone: status == TransportStatus.active ? BadgeTone.success : BadgeTone.neutral,
    );
  }
}

/// A confirm dialog followed by [action]; reports success/failure through
/// the messenger captured BEFORE the await, since the list re-fetches and
/// unmounts the calling row.
Future<void> confirmAndRun(
  BuildContext context, {
  required String title,
  required String message,
  required String successMessage,
  required Future<void> Function() action,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
  } catch (error) {
    final failure = error is Failure ? error : Failure.unknown(error.toString());
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

/// Runs [action] (no confirmation) and reports through a pre-captured
/// messenger - for activate/deactivate toggles.
Future<void> runAndReport(
  BuildContext context, {
  required String successMessage,
  required Future<void> Function() action,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
  } catch (error) {
    final failure = error is Failure ? error : Failure.unknown(error.toString());
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}
