import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../application/signed_in_sessions_notifier.dart';
import '../data/models/signed_in_session.dart';

/// Where this account is signed in, with a way to sign any other device out
/// (Phase 21, docs/security.md).
///
/// For the phone left on a staffroom table, or a password typed on a
/// borrowed laptop. A session also ends on its own after a week unused and a
/// month regardless - the dialog says so, so nobody thinks they are signed in
/// somewhere forever.
class SignedInDevicesDialog extends ConsumerStatefulWidget {
  const SignedInDevicesDialog({super.key});

  @override
  ConsumerState<SignedInDevicesDialog> createState() => _SignedInDevicesDialogState();
}

class _SignedInDevicesDialogState extends ConsumerState<SignedInDevicesDialog> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final message = await action();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(mounted ? failure.localizedMessage(context) : failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut(SignedInSession session) {
    final l10n = context.l10n;
    return _run(() async {
      await ref.read(signedInSessionsNotifierProvider.notifier).signOut(session.id);
      return l10n.staffSignedOutOf(session.deviceLabel);
    });
  }

  Future<void> _signOutOthers() async {
    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      title: l10n.staffSignOutOthersQ,
      message: l10n.staffSignOutOthersBody,
      confirmLabel: l10n.staffSignOutOthers,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() async {
      final ended = await ref.read(signedInSessionsNotifierProvider.notifier).signOutOthers();
      return l10n.staffSignedOutOthers(ended);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(signedInSessionsNotifierProvider);
    final hasOthers = sessions.value?.any((session) => !session.isCurrent) ?? false;
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.staffSignedInDevices),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.staffSessionLifetime, style: muted),
            const SizedBox(height: 12),
            Flexible(
              child: AsyncValueView<List<SignedInSession>>(
                value: sessions,
                onRetry: () => ref.invalidate(signedInSessionsNotifierProvider),
                data: (context, rows) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final session in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          session.device.contains('Android') || session.device.contains('iOS')
                              ? Icons.phone_android
                              : Icons.computer,
                        ),
                        title: Text(session.deviceLabel),
                        subtitle: Text(
                          [
                            if (session.lastUsedLabel != null) l10n.staffLastUsed(session.lastUsedLabel!),
                            if (session.signedInLabel != null) l10n.staffSignedInAt(session.signedInLabel!),
                          ].join('\n'),
                        ),
                        isThreeLine: session.lastUsedLabel != null && session.signedInLabel != null,
                        trailing: session.isCurrent
                            ? Chip(label: Text(l10n.staffThisDevice))
                            : TextButton(
                                onPressed: _busy ? null : () => _signOut(session),
                                child: Text(l10n.staffSignOut),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy || !hasOthers ? null : _signOutOthers, child: Text(l10n.staffSignOutAllOthers)),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.staffClose)),
      ],
    );
  }
}
