import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_notifier.dart';
import '../data/models/module_setting.dart';
import '../data/module_settings_repository.dart';

/// Every module for one school. The school id is the family key so a Super
/// Admin switching schools reloads rather than showing the last school's
/// switches; a School Admin passes null and gets their own.
final moduleSettingsNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<ModuleSettingsNotifier, List<ModuleSetting>, int?>(ModuleSettingsNotifier.new);

/// A failed switch or save leaves the loaded list in place and lets the
/// error through to the card, which knows which control to point at; only a
/// failed load puts the whole screen into its error state.
class ModuleSettingsNotifier extends AsyncNotifier<List<ModuleSetting>> {
  ModuleSettingsNotifier(this.schoolId);

  final int? schoolId;

  @override
  Future<List<ModuleSetting>> build() => ref.read(moduleSettingsRepositoryProvider).list(schoolId: schoolId);

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(moduleSettingsRepositoryProvider).list(schoolId: schoolId));
  }

  /// Moves one switch and nothing else. Exactly one of the two is passed.
  Future<void> updateSwitch(String module, {bool? platformEnabled, bool? schoolEnabled}) async {
    final saved = await ref
        .read(moduleSettingsRepositoryProvider)
        .update(module, schoolId: schoolId, platformEnabled: platformEnabled, schoolEnabled: schoolEnabled);

    _replace(saved);

    // The sidebar gates on the session's module map: re-read it so a module
    // just switched off disappears now, not at the next sign-in. A Super
    // Admin configuring some other school has nothing to refresh.
    if (schoolId == null) await ref.read(authNotifierProvider.notifier).refreshSession();
  }

  /// Saves one module's settings; the switches are left as they are.
  Future<void> saveSettings(String module, Map<String, Object?> settings) async {
    final saved = await ref
        .read(moduleSettingsRepositoryProvider)
        .update(module, schoolId: schoolId, settings: settings);

    _replace(saved);
  }

  void _replace(ModuleSetting saved) {
    state = state.whenData((rows) => [for (final row in rows) row.module == saved.module ? saved : row]);
  }
}
