/// A browser tab has no foreground service, and needs none: it is a tab on
/// somebody's desk, not a phone in a cradle. Both calls do nothing.
Future<void> start({required String title, required String body}) async {}

Future<void> stop() async {}
