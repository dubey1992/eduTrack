import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The set-password code from the link, held in memory once the router has
/// taken it out of the address (docs/security.md, "The 2026-10-26 review"):
/// a one-time secret has no business staying in a shared computer's history.
final resetCodeProvider = NotifierProvider<ResetCodeNotifier, String?>(ResetCodeNotifier.new);

class ResetCodeNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void hold(String code) => state = code;
}
