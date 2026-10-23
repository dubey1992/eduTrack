import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/battery_guard.dart';

/// Why a bus disappears from the school's map, and how to stop it.
///
/// Android's own battery saver can be asked from code, and the button here
/// does. What cannot be asked for is the layer Xiaomi, Oppo and Vivo add on
/// top: it kills foreground services on its own schedule, lives in a
/// different place on every phone, and has no API. So the rest of this
/// screen is instructions, by make, for a person to follow once
/// (docs/driver-app.md, D4.4).
class BatteryHelpScreen extends ConsumerStatefulWidget {
  const BatteryHelpScreen({super.key});

  @override
  ConsumerState<BatteryHelpScreen> createState() => _BatteryHelpScreenState();
}

class _BatteryHelpScreenState extends ConsumerState<BatteryHelpScreen> {
  bool _asking = false;

  Future<void> _ask() async {
    if (_asking) return;
    setState(() => _asking = true);

    final exempt = await ref.read(batteryGuardProvider).askForExemption();

    if (!mounted) return;
    setState(() => _asking = false);
    ref.invalidate(phoneMayStopSharingProvider);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            exempt
                ? 'Done. This phone will keep reporting with the screen off.'
                : 'Not changed. The steps below do the same thing by hand.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final exempt = ref.watch(phoneMayStopSharingProvider).value == false;

    return Scaffold(
      appBar: AppBar(title: const Text('Keep the bus on the map')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Why the school sometimes loses the bus', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'While a trip is running, this phone sends its position to the school so the office and '
            'parents can see where the bus is. Most phones stop apps they think you are not using - '
            'and a phone in a cradle with its screen off looks exactly like an app nobody is using.\n\n'
            'These two settings tell the phone this one is different. You only have to do it once.',
          ),
          const SizedBox(height: 24),
          _Step(
            number: 1,
            title: 'Allow it to run in the background',
            body: exempt
                ? 'Already allowed on this phone.'
                : 'This is the setting Android itself controls, and the button below opens it.',
            trailing: exempt
                ? Icon(Icons.check_circle, color: context.appColors.success)
                : FilledButton(
                    key: const Key('allow-background'),
                    onPressed: _asking ? null : _ask,
                    child: const Text('Allow'),
                  ),
          ),
          const SizedBox(height: 16),
          _Step(
            number: 2,
            title: 'Turn off your phone maker\'s battery saver for this app',
            body:
                'This one is not the same on every phone, and no app can change it for you. '
                'Find your make below.',
          ),
          const SizedBox(height: 8),
          for (final make in _makes)
            ExpansionTile(
              key: Key('make-${make.name.toLowerCase()}'),
              title: Text(make.name),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (final step in make.steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(step)),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          Text(
            'If you are not sure which make your phone is, show this screen to your school office.',
            style: TextStyle(color: context.appColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body, this.trailing});

  final int number;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            '$number',
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body, style: TextStyle(color: context.appColors.muted)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class _Make {
  const _Make(this.name, this.steps);

  final String name;
  final List<String> steps;
}

/// The makes that actually kill foreground services, and the path through
/// each one's settings. Written as what a driver reads on the screen in
/// front of them, not as menu trees that change with every OS update.
const _makes = [
  _Make('Xiaomi, Redmi or POCO', [
    'Settings > Apps > Manage apps > School365ai Driver > Battery saver > No restrictions.',
    'On the same screen, turn on Autostart.',
    'Open Recent apps, swipe down on this app\'s card and tap the padlock so it is not cleared.',
  ]),
  _Make('Oppo, Realme or OnePlus', [
    'Settings > Battery > Power saving > App battery usage (or App battery management).',
    'Find School365ai Driver and choose Allow background activity, or Don\'t optimise.',
    'Turn on Allow auto launch for this app.',
  ]),
  _Make('Vivo or iQOO', [
    'Settings > Battery > Background power consumption management > School365ai Driver > Allow high background power consumption.',
    'Settings > Apps > Autostart, and turn it on for this app.',
  ]),
  _Make('Samsung', [
    'Settings > Apps > School365ai Driver > Battery > Unrestricted.',
    'Settings > Battery > Background usage limits, and make sure this app is not in Sleeping apps or Deep sleeping apps.',
  ]),
  _Make('Any other phone', [
    'Settings > Apps > School365ai Driver > Battery, and choose the least restricted option offered.',
    'If there is an Autostart or Auto launch setting, turn it on.',
  ]),
];
