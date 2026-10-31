// school365ai.com's public pages (docs/seo.md, S2).
//
// The app lived at the site root and routed after a '#', so every link it
// ever sent - set-password and reset emails, the Play Store listing,
// bookmarks - reads https://school365ai.com/#/something. A server never
// sees what follows the '#', so those now arrive at the homepage. This
// sends them on to the same screen of the app, which lives at /app/.
// Loaded first in <head>, so the homepage never flashes on the way.
//
// Checked again on 'hashchange': an address typed or pasted while a public
// page is already open changes only the part after the '#', which does not
// reload the page, so the first check never sees it.
(function () {
  function forward() {
    var hash = window.location.hash;
    if (hash.indexOf('#/') === 0) {
      window.location.replace('/app/' + hash);
    }
  }

  forward();
  window.addEventListener('hashchange', forward);
})();
