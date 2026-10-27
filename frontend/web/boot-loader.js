// Takes away the School365ai mark index.html shows while the app downloads,
// the moment the app has drawn its first frame. Its own file rather than
// inline, because the page's security policy runs no inline script.
window.addEventListener('flutter-first-frame', function () {
  var loader = document.getElementById('boot-loader');
  if (loader) loader.remove();
});
