// கணக்கபிள்ளை — Service Worker
// Caches app files for offline use

const CACHE_NAME = 'kanakkupillai-v3';
const CACHE_URLS = [
  '/Kannakupilai/index.html',
  '/Kannakupilai/manifest.json',
  '/Kannakupilai/icon-192.png',
  '/Kannakupilai/icon-512.png',
  'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&family=Noto+Sans+Tamil:wght@400;600;700&display=swap',
  'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js'
];

// ── INSTALL: Cache all static files ──
self.addEventListener('install', e => {
  console.log('[SW] Installing...');
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      console.log('[SW] Caching files');
      return cache.addAll(CACHE_URLS).catch(err => {
        console.log('[SW] Cache addAll partial fail:', err);
      });
    })
  );
  self.skipWaiting();
});

// ── ACTIVATE: Remove old caches ──
self.addEventListener('activate', e => {
  console.log('[SW] Activating...');
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => {
          console.log('[SW] Deleting old cache:', k);
          return caches.delete(k);
        })
      )
    )
  );
  self.clients.claim();
});

// ── FETCH: Cache first, then network ──
self.addEventListener('fetch', e => {
  const url = e.request.url;

  // Skip Firebase & Google APIs — always network
  if (url.includes('firestore.googleapis.com') ||
      url.includes('firebase') ||
      url.includes('googleapis.com/identitytoolkit') ||
      url.includes('securetoken') ||
      url.includes('gstatic.com/firebasejs')) {
    return; // Let browser handle Firebase calls
  }

  // For app HTML files — Network first, then cache fallback
  if (url.includes('.html')) {
    e.respondWith(
      fetch(e.request)
        .then(res => {
          // Update cache with fresh copy
          const copy = res.clone();
          caches.open(CACHE_NAME).then(c => c.put(e.request, copy));
          return res;
        })
        .catch(() => caches.match(e.request))
    );
    return;
  }

  // For fonts, scripts, assets — Cache first
  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(res => {
        if (!res || res.status !== 200) return res;
        const copy = res.clone();
        caches.open(CACHE_NAME).then(c => c.put(e.request, copy));
        return res;
      }).catch(() => cached);
    })
  );
});

// ── BACKGROUND SYNC (when back online) ──
self.addEventListener('sync', e => {
  if (e.tag === 'sync-entries') {
    console.log('[SW] Background sync triggered');
  }
});

// ── PUSH NOTIFICATIONS (future) ──
self.addEventListener('push', e => {
  const data = e.data?.json() || { title: 'கணக்கபிள்ளை', body: 'New notification' };
  e.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: '/Kannakupilai/icon-192.png',
      badge: '/Kannakupilai/icon-192.png',
      vibrate: [200, 100, 200]
    })
  );
});
