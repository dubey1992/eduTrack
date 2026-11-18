import 'package:flutter/material.dart';

/// Flutter's date range picker, as a popup rather than a whole page.
///
/// In its calendar mode the stock picker takes the size of the screen
/// (`MediaQuery.sizeOf`), so on a laptop it covered the reports page from
/// edge to edge (2026-11-18). On anything wider than a phone it is told the
/// screen is popup-sized instead, and sits in the middle at that size; on a
/// phone it keeps the full screen, which is what a phone wants.
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String? helpText,
}) {
  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    helpText: helpText,
    builder: (context, child) => CompactDateRangePicker(child: child!),
  );
}

/// Shrinks the range picker it wraps to [popupSize] on screens wider than
/// [phoneWidth] - or to what fits, on a short window.
class CompactDateRangePicker extends StatelessWidget {
  const CompactDateRangePicker({super.key, required this.child});

  static const phoneWidth = 600.0;
  static const popupSize = Size(420, 600);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width < phoneWidth) return child;

    final size = Size(popupSize.width, popupSize.height.clamp(360.0, media.size.height - 48));

    return MediaQuery(
      data: media.copyWith(size: size),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}
