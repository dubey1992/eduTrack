import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../my_trip/data/voice_search.dart';
import '../../my_trip/data/voice_search_io.dart'
    if (dart.library.js_interop) '../../my_trip/data/voice_search_web.dart'
    as platform;

/// Speaking a test's marks on the marks sheet (docs/mobile-apps-review.md,
/// M12, 1.7): the same phone recogniser as the trip sheet's name search
/// (driver app, D8), listening longer - a run of marks takes more than a name.
///
/// None on the web: the button is not shown there. Tests swap in a fake.
final marksDictationProvider = Provider<VoiceSearch>(
  (ref) => platform.createVoiceSearch(listenFor: const Duration(seconds: 30), pauseFor: const Duration(seconds: 3)),
);
