'use strict';

// The web app's offline copy (docs/offline-web.md, O1).
//
// Keeps the app's own files - and the fonts it uses - on the computer, so the
// app opens with no internet. It never touches the API: schools' data is not
// cached here, and every request to api.school365ai.com goes straight to the
// network exactly as without this file.
//
// Network first, always: while online every file is fetched fresh, so a new
// release is picked up as soon as it is deployed and nothing ever runs from
// a stale copy. Only when the network fails is the kept copy used.
//
// Switching it off: set ENABLED to false and deploy. Every browser that
// checks this file (every visit; it is served "no-cache") then drops its
// copy and unregisters this worker.

const ENABLED = true;
const CACHE = 'school365ai-app-v1';
const FONT_HOSTS = ['fonts.gstatic.com', 'fonts.googleapis.com'];

// What the app needs to start, fetched on install so the first offline visit
// works even if a screen was never opened. A file missing from a build is
// skipped, never a reason to fail the install.
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'boot-loader.js',
  'manifest.json',
  'favicon.png?v=4',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  if (!ENABLED) return;
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.all(SHELL.map((path) => cache.add(path).catch(() => undefined))),
    ),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const name of await caches.keys()) {
        if (name.startsWith('school365ai-app') && (name !== CACHE || !ENABLED)) await caches.delete(name);
      }
      if (!ENABLED) {
        await self.registration.unregister();
        return;
      }
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  if (!ENABLED) return;
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  const scope = new URL(self.registration.scope);
  const ownFile = url.origin === scope.origin && url.pathname.startsWith(scope.pathname);
  const font = FONT_HOSTS.includes(url.hostname);
  // Everything else - the API above all - is none of this worker's business.
  if (!ownFile && !font) return;
  if (ownFile && url.pathname.endsWith('/offline-sw.js')) return;

  event.respondWith(networkFirst(request, scope));
});

async function networkFirst(request, scope) {
  const cache = await caches.open(CACHE);
  try {
    const response = await fetch(request);
    // A font from Google answers "opaque" (no CORS); it is still the font.
    if (response.ok || response.type === 'opaque') {
      cache.put(request, response.clone()).catch(() => undefined);
    }
    return response;
  } catch (error) {
    const kept = await cache.match(request);
    if (kept) return kept;
    // Any address inside the app opens the app; it routes itself by #.
    if (request.mode === 'navigate') {
      const shell = (await cache.match(scope.href)) || (await cache.match(new URL('index.html', scope).href));
      if (shell) return shell;
    }
    throw error;
  }
}
