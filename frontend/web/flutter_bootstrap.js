{{flutter_js}}
{{flutter_build_config}}

// How the web app starts (docs/offline-web.md, O1).
//
// Two things differ from Flutter's own start-up script:
//
// - The drawing engine (CanvasKit) is loaded from this site's own canvaskit/
//   folder, which the build already carries, instead of Google's servers -
//   so that once it has been kept on the computer, the app opens with no
//   internet at all.
// - Flutter's own service worker is not loaded (Flutter has retired it; it
//   only unregisters itself). Ours, offline-sw.js, is registered instead.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});

// Kept on the computer by offline-sw.js: the app's own files and its fonts,
// never anything from the API. A browser without service workers simply
// runs the app online, as before.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('offline-sw.js').catch(function (error) {
      console.warn('The offline copy of the app could not be set up:', error);
    });
  });
}
