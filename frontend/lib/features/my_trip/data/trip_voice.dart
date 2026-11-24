import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'trip_offline_store.dart';

/// Says a short sentence aloud on the bus - "Next stop Green Park, 4
/// children to pick up" (docs/mobile-apps-review.md, M7, 3.2).
///
/// The phone's own text-to-speech: nothing is sent anywhere. Swappable in
/// tests.
abstract class TripVoice {
  Future<void> say(String sentence);
}

final tripVoiceProvider = Provider<TripVoice>((ref) => PhoneTripVoice());

class PhoneTripVoice implements TripVoice {
  FlutterTts? _tts;

  @override
  Future<void> say(String sentence) async {
    try {
      final tts = _tts ??= FlutterTts();
      // A newer sentence replaces one still being said: the bus has moved on.
      await tts.stop();
      await tts.setSpeechRate(0.45);
      await tts.speak(sentence);
    } catch (error) {
      // A phone with no speech engine says nothing; the screen still shows it.
      debugPrint('Speaking "$sentence" failed: $error');
    }
  }
}

/// Whether the prompts are spoken on this phone. On until the crew mutes
/// them; remembered for the next trip.
final tripVoiceOnProvider = NotifierProvider<TripVoiceOn, bool>(TripVoiceOn.new);

class TripVoiceOn extends Notifier<bool> {
  @override
  bool build() {
    Future.microtask(() async {
      final saved = await ref.read(tripOfflineStoreProvider).readSpeakPrompts();
      if (saved != null && ref.mounted) state = saved;
    });
    return true;
  }

  Future<void> set(bool on) async {
    state = on;
    await ref.read(tripOfflineStoreProvider).saveSpeakPrompts(on);
  }
}
