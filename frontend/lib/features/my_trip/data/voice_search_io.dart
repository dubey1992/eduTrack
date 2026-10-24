import 'dart:async';
import 'dart:developer' as developer;

import 'package:speech_to_text/speech_to_text.dart';

import 'voice_search.dart';

VoiceSearch createVoiceSearch() => SpeechVoiceSearch();

/// The phone's own speech recogniser, through the speech_to_text plugin.
///
/// Nothing leaves the app but what Android's recogniser does with it, which
/// is the same as the keyboard's microphone key; there is no account, key or
/// server of ours involved.
class SpeechVoiceSearch implements VoiceSearch {
  final _speech = SpeechToText();

  /// Whether the recogniser has been set up. Done on the first tap, not
  /// before: setting it up is what shows the microphone permission prompt,
  /// and that prompt belongs to somebody who has just asked to speak, not
  /// to somebody who has just opened their trip.
  bool _ready = false;

  /// Never longer than this. A crew member who tapped the microphone and
  /// was interrupted should not find the phone still listening a minute on.
  static const _listenFor = Duration(seconds: 8);

  /// A pause this long means the name has been said.
  static const _pauseFor = Duration(seconds: 2);

  /// A phone build always offers the button; whether this particular phone
  /// will listen is found out on the tap, and said then.
  @override
  Future<bool> isAvailable() async => true;

  Future<bool> _setUp() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onError: (error) => developer.log('Speech recognition error', name: 'voice', error: error.errorMsg),
      );
    } on Object catch (error) {
      developer.log('Speech recognition unavailable', name: 'voice', error: error);
      _ready = false;
    }
    return _ready;
  }

  @override
  Stream<String> listen() {
    final controller = StreamController<String>();

    Future<void> run() async {
      if (!await _setUp()) {
        if (!controller.isClosed) {
          controller.addError(StateError('This phone will not listen: permission refused or no recogniser.'));
          await controller.close();
        }
        return;
      }
      try {
        await _speech.listen(
          onResult: (result) {
            if (controller.isClosed) return;
            controller.add(result.recognizedWords);
            if (result.finalResult) controller.close();
          },
          listenOptions: SpeechListenOptions(
            listenFor: _listenFor,
            pauseFor: _pauseFor,
            partialResults: true,
            cancelOnError: true,
          ),
        );
      } on Object catch (error) {
        developer.log('Could not start listening', name: 'voice', error: error);
        if (!controller.isClosed) await controller.close();
      }
    }

    // The recogniser may stop without a final result - nothing said, or an
    // error it swallowed. Watching for that keeps the field from showing a
    // microphone that is "listening" to silence for ever.
    final watch = Timer(_listenFor + const Duration(seconds: 2), () {
      if (!controller.isClosed) controller.close();
    });

    controller.onCancel = () async {
      watch.cancel();
      await stop();
    };
    unawaited(run());

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
  }
}
