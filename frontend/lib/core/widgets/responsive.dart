import 'package:flutter/material.dart';

/// Breakpoint used across the app to switch between the mobile layout
/// (lists/cards/bottom sheets) and the desktop/tablet layout (sidebar/data
/// tables), matching the prototype's behavior. See backend CLAUDE.md rule 8.
class Breakpoints {
  const Breakpoints._();

  static const double desktop = 1100;
}

/// Picks [desktop] or [mobile] based on the available width, so screens
/// don't hand-roll their own MediaQuery breakpoint checks.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.mobile, required this.desktop});

  final WidgetBuilder mobile;
  final WidgetBuilder desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth >= Breakpoints.desktop ? desktop(context) : mobile(context);
      },
    );
  }
}

extension ResponsiveContext on BuildContext {
  bool get isDesktop => MediaQuery.sizeOf(this).width >= Breakpoints.desktop;
}
