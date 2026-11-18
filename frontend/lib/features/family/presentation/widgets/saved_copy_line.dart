import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/date_format.dart';
import '../../application/family_offline.dart';
import 'family_widgets.dart';

/// "No connection. Showing what was true at 9:40 AM." - above a Family
/// screen showing the copy saved on the phone (docs/mobile-apps-review.md,
/// 2.2). Nothing at all while the screen has the server's answer.
class SavedCopyLine extends ConsumerWidget {
  const SavedCopyLine({super.key, required this.name});

  /// The copy's name, as FamilyApi saves it: `fees:12`.
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = ref.watch(familyOfflineProvider.select((copies) => copies[name]));
    if (at == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    final when = sameDay ? DateFormat('h:mm a').format(at) : '${formatDate(at)} ${DateFormat('h:mm a').format(at)}';

    return Padding(
      key: Key('family-saved-copy-$name'),
      padding: const EdgeInsets.only(bottom: 10),
      child: UpdatedLine(text: 'No connection. Showing what was true at $when.', stale: true),
    );
  }
}
