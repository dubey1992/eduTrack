import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_search_io.dart' if (dart.library.js_interop) 'voice_search_web.dart' as platform;

/// Hearing a child's name instead of typing it (docs/driver-app.md, D8).
///
/// Behind an interface for the usual three reasons: the web portal has no
/// use for it, tests must not reach the phone's recogniser, and the search
/// field has to work exactly the same on a phone that cannot listen - the
/// microphone button simply is not there.
abstract class VoiceSearch {
  /// Whether to offer a microphone at all. Cheap and silent: it says what
  /// kind of build this is, never asks the phone anything, and above all
  /// never shows the permission prompt - that belongs to the first tap on
  /// the button, not to opening the trip.
  Future<bool> isAvailable();

  /// Listens for one utterance. The words heard arrive as they firm up, so
  /// the field can show them while the crew is still speaking; the stream
  /// closes when the speaker pauses, the time runs out, or nothing was heard.
  /// It errors when the phone will not listen - permission refused, no
  /// recogniser installed - so the field can say so once.
  Stream<String> listen();

  /// Stops listening early. Safe when nothing is being heard.
  Future<void> stop();
}

final voiceSearchProvider = Provider<VoiceSearch>((ref) => platform.createVoiceSearch());
