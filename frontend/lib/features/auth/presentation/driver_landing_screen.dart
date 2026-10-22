import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 24),
                      ),
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
                    'Your trip sheet, on this phone.',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'For the driver and the attendant on the bus. Everything you '
                    'need for the run, and nothing else from the school.',
                    style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant, height: 1.45),
                  ),
                  const SizedBox(height: 28),
                  const _Point(
                    icon: Icons.play_circle_outline,
                    title: 'Start the run',
                    body: "Today's routes are waiting when you open the app. One tap starts the pickup or the drop.",
                  ),
                  const _Point(
                    icon: Icons.how_to_reg_outlined,
                    title: 'Tick each child on and off',
                    body: 'Boarded, dropped or absent. The school sees it, and the parents are told.',
                  ),
                  const _Point(
                    icon: Icons.wifi_off_outlined,
                    title: 'Works without signal',
                    body: 'Marks are kept on the phone and sent the moment you are back in range. Nothing is lost on the road.',
                  ),
                  const _Point(
                    icon: Icons.call_outlined,
                    title: "Call a child's parent",
                    body:
                        'One button opens the dialler. You never see the number, and the call is recorded in the log.',
                  ),
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
                          registered ? 'To sign in you need' : 'Before you start you need',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          registered
                              ? 'Your mobile number and the 4-digit passcode you chose on this phone.'
                              : 'Your mobile number, and an 8-digit code from your school office. '
                                    'The code works for 24 hours. You choose a 4-digit passcode while '
                                    'setting up, and after that the passcode is all you need.',
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
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: Text(registered ? 'Sign in' : 'Set up this phone'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Lost your phone, or forgotten the passcode? Your school office '
                    'can unlock your account and give you a new code.',
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
