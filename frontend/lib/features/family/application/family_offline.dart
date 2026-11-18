import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which Family screens are showing a copy saved on the phone right now,
/// and from when (docs/mobile-apps-review.md, 2.2). Keyed by the copy's
/// name (`fees:12`); absent means the screen has the server's answer.
///
/// The API writes here as each answer comes - fresh, or the saved copy for
/// want of signal - and each screen reads its own name to say so.
final familyOfflineProvider = NotifierProvider<FamilyOffline, Map<String, DateTime>>(FamilyOffline.new);

class FamilyOffline extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() => const {};

  void fresh(String name) {
    if (!state.containsKey(name)) return;
    state = {...state}..remove(name);
  }

  void old(String name, DateTime at) => state = {...state, name: at};
}
