import 'package:flutter/material.dart';

import '../../data/models/staff_profile.dart';

/// An employee's email address, or a muted "No email" for a Bus Attendant
/// added without one - whose stored address is a placeholder that must never
/// be shown as if somebody could write to it.
class StaffEmailText extends StatelessWidget {
  const StaffEmailText({super.key, required this.profile, this.style});

  final StaffProfile profile;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (profile.hasEmail) return Text(profile.email, style: style);

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Text(
      'No email',
      style: (style ?? const TextStyle()).copyWith(color: muted, fontStyle: FontStyle.italic),
    );
  }
}
