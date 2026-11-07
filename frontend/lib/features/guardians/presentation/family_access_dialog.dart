import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/guardians_notifier.dart';
import '../data/guardian_repository.dart';
import '../data/models/guardian_link.dart';

/// A guardian's sign-in to the School365ai Family app, for the school office
/// (docs/parent-student-app.md, F0, decision D1).
///
/// The office gives the parent a one-time setup code - printed on a letter,
/// or read out - and the parent registers their own phone with it and
/// chooses a passcode. The code is shown once and never again.
class FamilyAccessDialog extends ConsumerStatefulWidget {
  const FamilyAccessDialog({super.key, required this.studentId, required this.link});

  final int studentId;
  final GuardianLink link;

  @override
  ConsumerState<FamilyAccessDialog> createState() => _FamilyAccessDialogState();
}

class _FamilyAccessDialogState extends ConsumerState<FamilyAccessDialog> {
  bool _consent = false;
  bool _busy = false;
  IssuedSetupCode? _issued;

  (int, int) get _key => (widget.studentId, widget.link.id);

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Failure catch (failure) {
      _say(failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCode() => _run(() async {
    final issued = await ref
        .read(guardianRepositoryProvider)
        .issueSetupCode(widget.studentId, widget.link.id, consent: _consent);
    setState(() => _issued = issued);
    await ref.read(familyAccessProvider(_key).notifier).refresh();
  });

  Future<void> _printLetter() => _run(() async {
    final bytes = await ref
        .read(guardianRepositoryProvider)
        .letter(widget.studentId, widget.link.id, consent: _consent);
    saveBytes(
      fileName: 'family-app-letter-${widget.link.name.replaceAll(' ', '-')}.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
    );
    setState(() => _issued = null);
    await ref.read(familyAccessProvider(_key).notifier).refresh();
    _say('Letter downloaded. Any earlier code no longer works.');
  });

  Future<void> _removePhone(FamilyPhone phone) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Remove ${phone.name}?',
      message:
          'It will be signed out and can no longer sign in. The parent can register a phone again with a new code.',
      confirmLabel: 'Remove phone',
      isDestructive: true,
    );
    if (!confirmed) return;

    await _run(() async {
      await ref.read(familyAccessProvider(_key).notifier).removePhone(phone);
      _say('${phone.name} removed.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(familyAccessProvider(_key));

    return AlertDialog(
      title: Text('Family app · ${widget.link.name}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 480, maxWidth: 480, maxHeight: 520),
        child: AsyncValueView<FamilyAccess>(
          value: access,
          onRetry: () => ref.read(familyAccessProvider(_key).notifier).refresh(),
          data: (context, access) => SingleChildScrollView(child: _body(context, access)),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }

  Widget _body(BuildContext context, FamilyAccess access) {
    final muted = context.appColors.muted;
    final needsConsent = access.consentAt == null;
    final canIssue = access.loginMobile != null && (!needsConsent || _consent) && !_busy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            StatusBadge(
              label: access.hasPasscode ? 'Signed up' : (access.setupCodePending ? 'Code issued' : 'Not signed up'),
              tone: access.hasPasscode ? BadgeTone.success : BadgeTone.neutral,
            ),
            if (access.isLocked) const StatusBadge(label: 'Locked for a few minutes', tone: BadgeTone.warning),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          access.loginMobile == null
              ? 'Add this guardian\'s mobile number first: it is what they sign in with.'
              : 'Signs in with ${access.loginMobile}.',
          style: TextStyle(color: muted),
        ),
        if (access.setupCodePending && access.setupCodeExpiresAt != null && _issued == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'A code is waiting, until ${formatDate(access.setupCodeExpiresAt!)}.',
              style: TextStyle(color: muted),
            ),
          ),
        if (_issued != null) ...[
          const SizedBox(height: 14),
          Container(
            key: const Key('family-issued-code'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Setup code - shown once'),
                SelectableText(
                  '${_issued!.code.substring(0, 4)} ${_issued!.code.substring(4)}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 3),
                ),
                Text('Works until ${formatDate(_issued!.expiresAt)}, on one phone.', style: TextStyle(color: muted)),
              ],
            ),
          ),
        ],
        if (needsConsent) ...[
          const SizedBox(height: 10),
          CheckboxListTile(
            key: const Key('family-consent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: (value) => setState(() => _consent = value ?? false),
            title: const Text('The guardian has agreed to use the Family app'),
            subtitle: const Text('Recorded with your name and today\'s date.'),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('family-print-letter'),
              onPressed: canIssue ? _printLetter : null,
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print sign-in letter'),
            ),
            OutlinedButton(
              key: const Key('family-show-code'),
              onPressed: canIssue ? _showCode : null,
              child: const Text('Show a code instead'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Either one makes a new code; any earlier one stops working.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        if (access.activeDevices.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Phones', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final phone in access.activeDevices)
            ListTile(
              key: Key('family-phone-${phone.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.phone_android_outlined),
              title: Text(phone.name),
              subtitle: Text(
                phone.lastUsedAt == null ? 'Not used yet' : 'Last used ${formatDate(phone.lastUsedAt!)}',
                style: TextStyle(color: muted),
              ),
              trailing: TextButton(onPressed: _busy ? null : () => _removePhone(phone), child: const Text('Remove')),
            ),
        ],
      ],
    );
  }
}
