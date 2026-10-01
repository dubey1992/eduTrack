import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'marketing_content.dart';

final marketingContentRepositoryProvider = Provider<MarketingContentRepository>(
  (ref) => MarketingContentRepository(ref.watch(dioClientProvider)),
);

class MarketingContentRepository {
  MarketingContentRepository(this._dio);

  final Dio _dio;

  /// The homepage's words. Needs no session: the page is served to anybody
  /// who types the address (docs/marketing-content.md).
  ///
  /// **Never throws.** Anything that goes wrong - no network, a 500, a
  /// shape nobody expected - comes back as the page that ships. A visitor
  /// reading about the product has no idea what an API is and should not
  /// be shown one failing.
  Future<MarketingContent> fetch() async {
    try {
      final response = await _dio.get('/marketing-content');
      final body = response.data;

      if (body is! Map<String, dynamic>) return const MarketingContent.asItShips();

      return MarketingContent.fromJson(body);
    } on DioException {
      return const MarketingContent.asItShips();
    } catch (_) {
      return const MarketingContent.asItShips();
    }
  }
}

/// The words for the homepage, with the shipped copy until they arrive.
///
/// Not an AsyncValue the page has to branch on: the hero must render on
/// the first frame, and "loading" and "failed" both mean "the page as it
/// ships" here. Keeping that in one place stops six widgets each deciding
/// what to show while they wait.
final marketingContentProvider = NotifierProvider<MarketingContentNotifier, MarketingContent>(
  MarketingContentNotifier.new,
);

class MarketingContentNotifier extends Notifier<MarketingContent> {
  @override
  MarketingContent build() {
    _load();

    return const MarketingContent.asItShips();
  }

  Future<void> _load() async {
    final content = await ref.read(marketingContentRepositoryProvider).fetch();

    if (content.changed.isNotEmpty) state = content;
  }
}
