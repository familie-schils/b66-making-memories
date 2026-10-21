// Making Memories – Service Worker
// Enables offline caching and PWA installability

const CACHE_NAME = 'making-memories-v2';
const PRECACHE = [
  './index.html',
  './manifest.json',
  './assets/icons/icon-192.png',
  './assets/icons/icon-512.png',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(PRECACHE))
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  // Navigation: network-first with index fallback when offline
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() => caches.match('./index.html'))
    );
    return;
  }

  // JS/JSON: network-first with cache fallback
  if (url.origin === self.location.origin && /\.(js|json)$/i.test(url.pathname)) {
    event.respondWith(
      fetch(request).then(response => {
        if (response && response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
        }
        return response;
      }).catch(() => caches.match(request))
    );
    return;
  }

  // Static assets: cache-first with network fallback
  event.respondWith(
    caches.match(request).then(cached => cached || fetch(request))
  );
});
