import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lock.dart';
import '../l10n/l10n.dart';

/// Puts the app lock over the whole app (docs/mobile-apps-review.md, 4.4).
///
/// Sits in MaterialApp.builder, above the router, so no screen can be
/// reached around it. It watches the app going to the background and
/// coming back, covers everything while locked, and - once, after signing
/// in, on a phone that can - offers to turn the lock on. The offer is the
/// app's own card, not a dialog: there is no navigator up here.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.signedIn, required this.child});

  /// Nobody signed in means nothing to protect: no lock, no offer.
  final bool signedIn;
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(appLockProvider.notifier).wentToBackground(),
      onShow: () => ref.read(appLockProvider.notifier).cameBack(),
    );
  }

  @override
  void didUpdateWidget(AppLockGate old) {
    super.didUpdateWidget(old);
    if (old.signedIn && !widget.signedIn) {
      // Signed out: the next person on this phone decides for themselves.
      ref.read(appLockProvider.notifier).forget();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final canLock = ref.watch(appLockAvailableProvider).value ?? false;
    final offer = widget.signedIn && lock.loaded && !lock.enabled && !lock.offered && canLock;

    return Stack(
      children: [
        // Hidden from screen readers too while locked.
        ExcludeSemantics(excluding: widget.signedIn && lock.locked, child: widget.child),
        if (widget.signedIn && lock.locked) const Positioned.fill(child: _LockScreen()),
        if (offer && !lock.locked) const Positioned(left: 0, right: 0, bottom: 0, child: _LockOffer()),
      ],
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen();

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Ask straight away; the button is for a second try.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final passed = await ref.read(appLockProvider.notifier).unlock();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !passed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      key: const Key('app-lock-screen'),
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                Text(context.l10n.coreLockedTitle, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  context.l10n.coreLockedHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                if (_failed) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.coreNotUnlocked,
                    key: const Key('app-lock-failed'),
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('app-lock-unlock'),
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: Text(context.l10n.coreUnlock),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LockOffer extends ConsumerStatefulWidget {
  const _LockOffer();

  @override
  ConsumerState<_LockOffer> createState() => _LockOfferState();
}

class _LockOfferState extends ConsumerState<_LockOffer> {
  bool _busy = false;
  String? _problem;

  Future<void> _turnOn() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final problem = await ref.read(appLockProvider.notifier).turnOn();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          key: const Key('app-lock-offer'),
          elevation: 6,
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.fingerprint_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(context.l10n.coreLockOfferTitle, style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(context.l10n.coreLockOfferBody, style: TextStyle(color: scheme.onSurfaceVariant)),
                if (_problem != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _problem!,
                    key: const Key('app-lock-offer-problem'),
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('app-lock-not-now'),
                      onPressed: _busy ? null : () => ref.read(appLockProvider.notifier).decline(),
                      child: Text(context.l10n.coreNotNow),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      key: const Key('app-lock-turn-on'),
                      onPressed: _busy ? null : _turnOn,
                      child: Text(context.l10n.coreTurnOn),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The switch for the settings screens: My Profile in the Staff app, Your
/// privacy in the Family app. Not shown on a phone that cannot lock.
class AppLockSwitch extends ConsumerStatefulWidget {
  const AppLockSwitch({super.key});

  @override
  ConsumerState<AppLockSwitch> createState() => _AppLockSwitchState();
}

class _AppLockSwitchState extends ConsumerState<AppLockSwitch> {
  bool _busy = false;
  String? _problem;

  Future<void> _change(bool on) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final notifier = ref.read(appLockProvider.notifier);
    String? problem;
    if (on) {
      problem = await notifier.turnOn();
    } else {
      await notifier.turnOff();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!(ref.watch(appLockAvailableProvider).value ?? false)) return const SizedBox.shrink();
    final lock = ref.watch(appLockProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('app-lock-switch'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.fingerprint_rounded),
          title: Text(context.l10n.coreAppLock),
          subtitle: Text(context.l10n.coreAppLockHint),
          value: lock.enabled,
          onChanged: _busy || !lock.loaded ? null : _change,
        ),
        if (_problem != null)
          Text(
            _problem!,
            key: const Key('app-lock-switch-problem'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
