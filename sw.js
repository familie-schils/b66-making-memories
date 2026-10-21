// Making Memories – Service Worker
// Enables offline caching and PWA installability

const CACHE_PREFIX = 'making-memories-';
const CACHE_NAME = `${CACHE_PREFIX}v3`;
const PRECACHE = [
  './index.html',
  './test-agent.html',
  './manifest.json',
  './assets/icons/icon-192.png',
  './assets/icons/icon-512.png',
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(PRECACHE);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  // Navigation: network-first with index fallback when offline
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request, { cache: 'no-cache' }).catch(async () =>
        (await caches.match(request)) || caches.match('./index.html')
      )
    );
    return;
  }

  // JS/JSON: network-first with cache fallback
  if (url.origin === self.location.origin && /\.(js|json)$/i.test(url.pathname)) {
    event.respondWith(
      fetch(request, { cache: 'no-cache' }).then(async response => {
        if (response && response.ok) {
          const copy = response.clone();
          await (await caches.open(CACHE_NAME)).put(request, copy);
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
