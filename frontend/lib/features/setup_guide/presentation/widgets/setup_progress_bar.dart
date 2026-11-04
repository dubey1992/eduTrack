import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/chart_palette.dart';

/// How far a school's setup has got, a segment per step (decided
/// 2026-11-04): the steps done are filled in a colour that moves with the
/// progress - orange under halfway, blue from halfway, green once every step
/// is done - and the steps still to do stay grey.
class SetupProgressBar extends StatelessWidget {
  const SetupProgressBar({super.key, required this.done, required this.total, this.height = 6});

  final int done;
  final int total;
  final double height;

  /// The colour the finished steps are drawn in, for [done] of [total].
  static Color colourFor(BuildContext context, int done, int total) {
    if (total > 0 && done >= total) return context.appColors.success;

    return done * 2 >= total ? ChartPalette.blue.strong(context) : ChartPalette.orange.strong(context);
  }

  @override
  Widget build(BuildContext context) {
    final filled = colourFor(context, done, total);
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Semantics(
      label: '$done of $total setup steps done',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var step = 0; step < total; step++) ...[
            if (step > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                key: Key('setup-step-$step'),
                height: height,
                decoration: BoxDecoration(
                  color: step < done ? filled : empty,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
