/// Everywhere that is not the web: the Maps SDK ships inside the app, so
/// there is nothing to fetch and nothing to wait for.
///
/// Android reads its key from the manifest rather than from this, which is
/// why the key is not a parameter anybody uses here. See docs/maps.md.
Future<void> ensureMapsReady(String browserKey) async {}
