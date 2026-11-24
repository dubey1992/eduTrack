import '../../../core/widgets/driver_mark.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../data/attendant_auth_repository.dart';

/// What the app is, before anybody signs in.
///
/// Written for the person on the bus, not for the office: short lines, no
/// product words, and the one thing they need to fetch before they can get
/// anywhere - the code from the school office. A driver who opens this in a
/// yard should be able to tell in ten seconds whether they can start now or
/// need to go and ask for something.
class DriverLandingScreen extends ConsumerStatefulWidget {
  const DriverLandingScreen({super.key});

  @override
  ConsumerState<DriverLandingScreen> createState() => _DriverLandingScreenState();
}

class _DriverLandingScreenState extends ConsumerState<DriverLandingScreen> {
  /// Null until the phone has been asked. A phone that has been set up
  /// before only needs its passcode, so the button says so rather than
  /// offering to set it up again.
  bool? _registered;

  @override
  void initState() {
    super.initState();
    _askThePhone();
  }

  Future<void> _askThePhone() async {
    final device = await ref.read(attendantAuthRepositoryProvider).registeredDevice();
    if (mounted) setState(() => _registered = device != null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final registered = _registered ?? false;
    final l10n = context.l10n;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // The shuttle, as on the launcher icon (scripts/driver_icon.py).
                      const DriverMark(key: Key('driver-mark'), size: 44),
                      const SizedBox(width: 12),
                      // Flexible, not bare: the name plus the mark is wider
                      // than a narrow phone, and a bare Row overflows rather
                      // than trimming.
                      Flexible(
                        child: Text(
                          'School365ai Driver',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text(
                    l10n.busLandingHeadline,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.busLandingIntro,
                    style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant, height: 1.45),
                  ),
                  const SizedBox(height: 28),
                  _Point(
                    icon: Icons.play_circle_outline,
                    title: l10n.busLandingStartTitle,
                    body: l10n.busLandingStartBody,
                  ),
                  _Point(
                    icon: Icons.how_to_reg_outlined,
                    title: l10n.busLandingTickTitle,
                    body: l10n.busLandingTickBody,
                  ),
                  _Point(
                    icon: Icons.wifi_off_outlined,
                    title: l10n.busLandingOfflineTitle,
                    body: l10n.busLandingOfflineBody,
                  ),
                  _Point(icon: Icons.call_outlined, title: l10n.busLandingCallTitle, body: l10n.busLandingCallBody),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          registered ? l10n.busLandingNeedSignIn : l10n.busLandingNeedSetUp,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          registered ? l10n.busLandingNeedSignInBody : l10n.busLandingNeedSetUpBody,
                          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('landing-continue'),
                      onPressed: () => context.go('/sign-in'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16),
                      ),
                      child: Text(registered ? l10n.busLandingSignIn : l10n.busLandingSetUp),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.busLandingLostPhone,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One thing the app does, said once.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
