import 'voice_search.dart';

VoiceSearch createVoiceSearch() => const NoVoiceSearch();

/// The web portal has no bus to be on and no microphone button to show; the
/// text search is all of it there.
class NoVoiceSearch implements VoiceSearch {
  const NoVoiceSearch();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Stream<String> listen() => const Stream.empty();

  @override
  Future<void> stop() async {}
}
