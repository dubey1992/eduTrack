import 'package:flutter/material.dart';

/// A horizontally scrolling host for a wide [DataTable], with an
/// always-visible thumb so the columns past the right edge are discoverable
/// on desktop (mouse wheels don't scroll sideways).
class HorizontalScrollTable extends StatefulWidget {
  const HorizontalScrollTable({super.key, required this.child});

  final Widget child;

  @override
  State<HorizontalScrollTable> createState() => _HorizontalScrollTableState();
}

class _HorizontalScrollTableState extends State<HorizontalScrollTable> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.child,
      ),
    );
  }
}
