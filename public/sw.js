// App-shell service worker: lets the installed app open with no signal.
// Caches ONLY this app's own static files (page, JS, CSS, icons). It never handles requests to other
// origins, so Supabase logins, tokens and data are never stored here.
// ponytail: old hashed JS/CSS from earlier deploys stay in this cache until CACHE is renamed; bump the
// version (v3, v4...) when the cache grows or on a big release.
const CACHE = 'aaa-shell-v2'
const SHELL = ['/', '/manifest.webmanifest', '/favicon.svg', '/icon-192.png', '/icon-512.png', '/icon-maskable-512.png']

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE)
      await cache.addAll(SHELL)
      // the page's hashed JS/CSS files, so the very first offline start works too
      const html = await (await fetch('/', { cache: 'no-store' })).text()
      const assets = [...html.matchAll(/(?:src|href)="(\/assets\/[^"]+)"/g)].map((m) => m[1])
      await cache.addAll(assets)
      await self.skipWaiting()
    })(),
  )
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) if (key !== CACHE) await caches.delete(key)
      await self.clients.claim()
    })(),
  )
})

self.addEventListener('fetch', (event) => {
  const req = event.request
  const url = new URL(req.url)
  if (req.method !== 'GET' || url.origin !== self.location.origin) return // Supabase etc.: never touched

  if (req.mode === 'navigate') {
    // network first so updates arrive; the cached page when there is no signal
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) {
            const copy = res.clone()
            caches.open(CACHE).then((c) => c.put('/', copy))
          }
          return res
        })
        .catch(() => caches.match('/', { ignoreVary: true })),
    )
    return
  }

  // static files: cached copy first (hashed names never change), else fetch and keep it
  event.respondWith(
    // ignoreVary: the page asks for scripts with an Origin header, the install step without one
    caches.match(req, { ignoreVary: true }).then(
      (hit) =>
        hit ||
        fetch(req).then((res) => {
          if (res.ok && (url.pathname.startsWith('/assets/') || SHELL.includes(url.pathname))) {
            const copy = res.clone()
            caches.open(CACHE).then((c) => c.put(req, copy))
          }
          return res
        }),
    ),
  )
})
