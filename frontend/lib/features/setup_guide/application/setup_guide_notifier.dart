import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/setup_guide.dart';
import '../data/setup_guide_repository.dart';

/// The School Admin's setup guide (docs/onboarding.md, O4). Re-read whenever
/// the guide or the dashboard opens, since every step is worked out from what
/// the school has just added elsewhere.
final setupGuideNotifierProvider = AsyncNotifierProvider<SetupGuideNotifier, SetupGuide>(SetupGuideNotifier.new);

class SetupGuideNotifier extends AsyncNotifier<SetupGuide> {
  @override
  Future<SetupGuide> build() => ref.read(setupGuideRepositoryProvider).show();

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(setupGuideRepositoryProvider).show());
  }

  /// Finished or hidden, for every admin of the school.
  Future<void> close() async {
    state = AsyncData(await ref.read(setupGuideRepositoryProvider).close());
  }

  Future<void> reopen() async {
    state = AsyncData(await ref.read(setupGuideRepositoryProvider).reopen());
  }
}

/// Whether the guide has already opened itself this session, so a School
/// Admin who leaves it for the dashboard is not sent straight back.
final setupGuideAutoOpenedProvider = NotifierProvider<SetupGuideAutoOpened, bool>(SetupGuideAutoOpened.new);

class SetupGuideAutoOpened extends Notifier<bool> {
  @override
  bool build() => false;

  void markOpened() => state = true;
}
