import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/app_lock_gate.dart';
import '../../../core/theme/app_colors.dart';
import 'widgets/family_widgets.dart';

/// "Your privacy" (docs/mobile-apps-review.md, 4.5): what the school's
/// system does with a parent's number and where the bus's location comes
/// from, in plain words.
///
/// Every line here is how the code behaves, not a promise on top of it:
/// who may see a guardian's number follows the school's permissions (the
/// office, the class's own teachers, whoever takes fees, the transport
/// office and the crew of the child's route); the live bus is offered only
/// while the child's own trip runs (family_bus.live_trip); and this build
/// drops every location permission in its manifest. Change the code, change
/// this page.
class FamilyPrivacyScreen extends StatelessWidget {
  const FamilyPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your privacy')),
      body: ListView(
        key: const Key('family-privacy'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _Fact(
            key: Key('family-privacy-number'),
            icon: Icons.contact_phone_rounded,
            title: 'Who can see your phone number',
            lines: [
              'The school office.',
              'Your child\'s own class teachers - not teachers of other classes.',
              'Staff who take fees, so they can call about a payment.',
              'If your child takes the school bus: the transport office, and the bus crew on your child\'s route, '
                  'so they can call you from the road.',
              'The school decides whether any other staff may see it.',
            ],
          ),
          const SizedBox(height: 12),
          const _Fact(
            key: Key('family-privacy-location'),
            icon: Icons.location_on_rounded,
            title: 'The bus on the map',
            lines: [
              'The location you see is the bus\'s, sent by the crew\'s phone while a trip runs.',
              'You can follow it only while your child\'s own trip is running - until they are dropped off '
                  'or marked as not on the bus.',
              'This app never asks for your phone\'s location.',
            ],
          ),
          const SizedBox(height: 12),
          _Fact(
            key: const Key('family-privacy-messages'),
            icon: Icons.notifications_active_outlined,
            title: 'What comes to this app',
            lines: const ['You choose which kinds of message the school sends to this app.'],
            action: TextButton(
              key: const Key('family-privacy-open-notifications'),
              onPressed: () => context.push('/notifications'),
              child: const Text('Choose notifications'),
            ),
          ),
          const SizedBox(height: 12),
          // The app lock (4.4), on a phone that can have one.
          const FamilyCard(child: AppLockSwitch()),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({super.key, required this.icon, required this.title, required this.lines, this.action});

  final IconData icon;
  final String title;
  final List<String> lines;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return FamilyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(icon: icon, title: title, colour: colours.info),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Icon(Icons.circle, size: 6, color: colours.muted),
                  ),
                  Expanded(child: Text(line, style: const TextStyle(height: 1.4))),
                ],
              ),
            ),
          if (action != null) Align(alignment: Alignment.centerRight, child: action),
        ],
      ),
    );
  }
}
