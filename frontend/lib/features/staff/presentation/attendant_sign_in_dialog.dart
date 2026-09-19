import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/school_clock.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/school_clock_provider.dart';
import '../application/attendant_access_notifier.dart';
import '../data/models/attendant_access.dart';
import '../data/models/staff_profile.dart';

/// A UTC instant from the API, on the school's clock: "09/10/2026 7:30 AM".
String _schoolDateTime(SchoolClock clock, String? iso) {
  final parsed = iso == null ? null : DateTime.tryParse(iso);
  if (parsed == null) return '-';

  return formatDateTime(clock.toSchoolTime(parsed));
}

/// How a Bus Attendant signs in: their mobile number, passcode, setup code
/// and registered phones - and the administrator's controls over them
/// (issue a setup code, remove a lost phone, unlock after five wrong tries).
/// See docs/maps.md, "The Bus Attendant".
class AttendantSignInDialog extends ConsumerStatefulWidget {
  const AttendantSignInDialog({super.key, required this.profile});

  final StaffProfile profile;

  @override
  ConsumerState<AttendantSignInDialog> createState() => _AttendantSignInDialogState();
}

class _AttendantSignInDialogState extends ConsumerState<AttendantSignInDialog> {
  bool _busy = false;
  String? _errorMessage;

  AttendantAccessNotifier get _notifier => ref.read(attendantAccessProvider(widget.profile.id).notifier);

  /// Runs one action at a time - a second tap while one is in flight does
  /// nothing - and shows a failure inside the panel, where it is read.
  Future<bool> _run(Future<void> Function() action, {String? successMessage}) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (successMessage != null) messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      return true;
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _issueSetupCode(AttendantAccess access) async {
    if (access.setupCodePending) {
      final clock = ref.read(schoolClockProvider);
      final replace = await confirmDialog(
        context,
        title: 'Replace the waiting setup code?',
        message:
            'A setup code issued earlier is still waiting to be used '
            '(valid until ${_schoolDateTime(clock, access.setupCodeExpiresAt)}). '
            'Issuing a new code replaces it, and the old code stops working.',
        confirmLabel: 'Issue new code',
      );
      if (!replace || !mounted) return;
    }

    AttendantSetupCode? issued;
    await _run(() async {
      issued = await _notifier.issueSetupCode();
    });

    if (issued != null && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SetupCodeDialog(attendantName: widget.profile.name, code: issued!),
      );
    }
  }

  Future<void> _removeDevice(AttendantDevice device) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Remove this phone?',
      message:
          'Sign out and remove ${device.displayName}? The attendant will need a new setup code to use that '
          'phone again.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() => _notifier.removeDevice(device), successMessage: '${device.displayName} was removed.');
  }

  Future<void> _unlock() async {
    await _run(
      () => _notifier.unlock(widget.profile.userId),
      successMessage: '${widget.profile.name} can sign in again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final accessState = ref.watch(attendantAccessProvider(widget.profile.id));
    final access = accessState.value;

    return AlertDialog(
      title: Text('Sign-in · ${widget.profile.name}'),
      content: ConstrainedBox(
        // Bounded so the loading spinner does not stretch the dialog to the
        // full height of the window before the answer arrives.
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 560, maxHeight: 520),
        child: SingleChildScrollView(
          child: AsyncValueView<AttendantAccess>(
            value: accessState,
            onRetry: () => _notifier.refresh(),
            data: (context, access) => _AccessDetails(
              access: access,
              busy: _busy,
              errorMessage: _errorMessage,
              onUnlock: _unlock,
              onRemoveDevice: _removeDevice,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (access != null)
          FilledButton.icon(
            onPressed: _busy ? null : () => _issueSetupCode(access),
            icon: const Icon(Icons.key_outlined, size: 18),
            label: const Text('Issue setup code'),
          ),
      ],
    );
  }
}

class _AccessDetails extends ConsumerWidget {
  const _AccessDetails({
    required this.access,
    required this.busy,
    required this.errorMessage,
    required this.onUnlock,
    required this.onRemoveDevice,
  });

  final AttendantAccess access;
  final bool busy;
  final String? errorMessage;
  final VoidCallback onUnlock;
  final ValueChanged<AttendantDevice> onRemoveDevice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(schoolClockProvider);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorMessage != null) ...[
          Text(errorMessage!, style: TextStyle(color: context.appColors.danger)),
          const SizedBox(height: 12),
        ],
        if (access.isLocked) ...[
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const StatusBadge(label: 'Locked after 5 wrong tries', tone: BadgeTone.danger),
              OutlinedButton(onPressed: busy ? null : onUnlock, child: const Text('Unlock')),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _Fact(label: 'Sign-in mobile', value: access.loginMobile),
        _Fact(
          label: 'Passcode',
          value: access.hasPasscode ? 'Set' : 'Not set up yet - issue a setup code',
          muted: !access.hasPasscode,
        ),
        _Fact(
          label: 'Setup code',
          value: access.setupCodePending
              ? 'Waiting to be used - valid until ${_schoolDateTime(clock, access.setupCodeExpiresAt)}'
              : 'None waiting',
          muted: !access.setupCodePending,
        ),
        const SizedBox(height: 16),
        Text('Registered phones', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('A passcode only works on a phone registered with a setup code.', style: muted.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        if (access.devices.isEmpty)
          Text('No phone registered yet.', style: muted)
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final device in access.devices)
                  ListTile(
                    dense: true,
                    leading: Icon(device.isActive ? Icons.smartphone : Icons.phonelink_erase_outlined),
                    title: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(device.displayName),
                        device.isActive
                            ? const StatusBadge(label: 'Active', tone: BadgeTone.success)
                            : const StatusBadge(label: 'Removed', tone: BadgeTone.neutral),
                      ],
                    ),
                    subtitle: Text(
                      'Registered ${_schoolDateTime(clock, device.registeredAt)} · '
                      'Last used ${_schoolDateTime(clock, device.lastUsedAt)}',
                    ),
                    trailing: device.isActive
                        ? TextButton(onPressed: busy ? null : () => onRemoveDevice(device), child: const Text('Remove'))
                        : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: mutedColor)),
          ),
          Expanded(
            child: Text(value, style: muted ? TextStyle(color: mutedColor) : null),
          ),
        ],
      ),
    );
  }
}

/// Shows a newly issued setup code - once. The server never shows it again,
/// so the dialog says so and cannot be dismissed by a stray tap outside it.
class SetupCodeDialog extends ConsumerWidget {
  const SetupCodeDialog({super.key, required this.attendantName, required this.code});

  final String attendantName;
  final AttendantSetupCode code;

  /// "12345678" -> "1234 5678": easier to read out and to type.
  static String spaced(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(value[i]);
    }
    return buffer.toString();
  }

  String _validity(SchoolClock clock) {
    final expires = DateTime.tryParse(code.expiresAt);
    if (expires == null) return 'Valid until ${code.expiresAt}';

    final hours = (expires.toUtc().difference(DateTime.now().toUtc()).inMinutes / 60).round();
    final until = _schoolDateTime(clock, code.expiresAt);
    if (hours < 1) return 'Valid until $until';

    return 'Valid for $hours ${hours == 1 ? 'hour' : 'hours'}, until $until';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(schoolClockProvider);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return AlertDialog(
      title: Text('Setup code for $attendantName'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SelectableText(
                spaced(code.setupCode),
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 4),
              ),
            ),
            const SizedBox(height: 8),
            Center(child: Text(_validity(clock), style: muted)),
            Center(child: Text('For mobile number ${code.loginMobile}', style: muted)),
            const SizedBox(height: 16),
            const Text(
              "On the attendant's phone: open the app, tap 'Bus attendant? Sign in with your mobile number', "
              'enter this number and code, and choose a 4-digit passcode.',
            ),
            const SizedBox(height: 12),
            Text(
              'This code is shown only once. Copy it or write it down before closing.',
              style: muted.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code.setupCode));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Setup code copied.')));
            }
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
