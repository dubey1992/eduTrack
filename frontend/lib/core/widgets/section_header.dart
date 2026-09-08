import 'package:flutter/material.dart';

/// Heading + trailing action row above a page's main content, matching the
/// prototype's `.section-title` pattern (e.g. "Users" + "+ Add User").
/// Used by every list-style screen (Users, Schools, Payments, and every
/// later phase's list screens) so they share one consistent header shape.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
        ],
      ),
    );
  }
}
