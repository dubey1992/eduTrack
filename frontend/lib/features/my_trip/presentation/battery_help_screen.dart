import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
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
      ..showSnackBar(SnackBar(content: Text(exempt ? context.l10n.busBatteryDone : context.l10n.busBatteryNotChanged)));
  }

  @override
  Widget build(BuildContext context) {
    final exempt = ref.watch(phoneMayStopSharingProvider).value == false;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.busBatteryTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.busBatteryWhy, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.busBatteryIntro),
          const SizedBox(height: 24),
          _Step(
            number: 1,
            title: l10n.busBatteryStep1Title,
            body: exempt ? l10n.busBatteryStep1Done : l10n.busBatteryStep1Body,
            trailing: exempt
                ? Icon(Icons.check_circle, color: context.appColors.success)
                : FilledButton(
                    key: const Key('allow-background'),
                    onPressed: _asking ? null : _ask,
                    child: Text(l10n.busBatteryAllow),
                  ),
          ),
          const SizedBox(height: 16),
          _Step(number: 2, title: l10n.busBatteryStep2Title, body: l10n.busBatteryStep2Body),
          const SizedBox(height: 8),
          for (final make in _makesIn(l10n))
            ExpansionTile(
              key: Key('make-${make.key}'),
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
          Text(l10n.busBatteryNotSure, style: TextStyle(color: context.appColors.muted)),
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
  const _Make(this.key, this.name, this.steps);

  /// The make in English, lower case - stays the same in every language.
  final String key;
  final String name;
  final List<String> steps;
}

/// The makes that actually kill foreground services, and the path through
/// each one's settings. Written as what a driver reads on the screen in
/// front of them, not as menu trees that change with every OS update.
/// The menu names stay in English in every language: they are what the
/// phone's own settings show.
List<_Make> _makesIn(AppLocalizations l10n) => [
  _Make('xiaomi, redmi or poco', l10n.busMakeXiaomi, [l10n.busMakeXiaomi1, l10n.busMakeXiaomi2, l10n.busMakeXiaomi3]),
  _Make('oppo, realme or oneplus', l10n.busMakeOppo, [l10n.busMakeOppo1, l10n.busMakeOppo2, l10n.busMakeOppo3]),
  _Make('vivo or iqoo', l10n.busMakeVivo, [l10n.busMakeVivo1, l10n.busMakeVivo2]),
  _Make('samsung', l10n.busMakeSamsung, [l10n.busMakeSamsung1, l10n.busMakeSamsung2]),
  _Make('any other phone', l10n.busMakeOther, [l10n.busMakeOther1, l10n.busMakeOther2]),
];
