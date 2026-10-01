import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/marketing_content_repository.dart';
import '../data/marketing_draft_repository.dart';
import '../data/models/marketing_draft.dart';

final marketingDraftNotifierProvider = AsyncNotifierProvider<MarketingDraftNotifier, MarketingDraft>(
  MarketingDraftNotifier.new,
);

/// The homepage as the Super Admin's editor sees it.
///
/// A failed save or publish leaves the loaded draft on screen and lets the
/// error through to the form, which marks up the box the server named;
/// only a failed load puts the whole screen into its error state.
class MarketingDraftNotifier extends AsyncNotifier<MarketingDraft> {
  @override
  Future<MarketingDraft> build() => ref.read(marketingDraftRepositoryProvider).get();

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(marketingDraftRepositoryProvider).get());
  }

  /// [document] is the whole form. A field left out of it was cleared, and
  /// the page falls back to the copy it ships with.
  Future<void> save(Map<String, String> document) async {
    state = AsyncData(await ref.read(marketingDraftRepositoryProvider).save(document));
  }

  /// Puts the draft in front of the world, then reads the row back so the
  /// screen shows the new "published" and stops offering to publish.
  Future<void> publish() async {
    final repository = ref.read(marketingDraftRepositoryProvider);

    await repository.publish();
    state = AsyncData(await repository.get());

    // The Super Admin is almost certainly about to look at the homepage to
    // check their work, and this app may already be holding the old words.
    ref.invalidate(marketingContentProvider);
  }
}
