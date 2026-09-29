/*
 * bullethub service worker - installability + fast reloads, nothing clever.
 *
 * - /app/assets/* (hashed, immutable): cache-first.
 * - Navigations: network-first; offline → last cached app shell, else a tiny
 *   offline page.
 * - Never touched: /api, /socket, /webhooks, /dev, video (Bunny is another
 *   origin anyway). Auth and playback must always hit the network.
 */
const VERSION = 'v1'
const ASSETS = `bullethub-assets-${VERSION}`
const SHELL = `bullethub-shell-${VERSION}`

self.addEventListener('install', () => self.skipWaiting())

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => ![ASSETS, SHELL].includes(k)).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

const OFFLINE_HTML = `<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sem conexão · bullethub</title><body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#060606;color:#fff;font-family:system-ui,sans-serif;text-align:center">
<div><p style="color:#f20024;font-weight:700;letter-spacing:.18em;font-size:12px">SEM CONEXÃO</p><h1 style="font-size:40px;margin:16px 0">Você está offline.</h1>
<p style="color:#bcbcbc">Assim que a internet voltar, é só recarregar.</p></div></body></html>`

self.addEventListener('fetch', (event) => {
  const req = event.request
  if (req.method !== 'GET') return
  const url = new URL(req.url)
  if (url.origin !== self.location.origin) return
  if (/^\/(api|socket|webhooks|dev|live|health)(\/|$)/.test(url.pathname)) return

  if (url.pathname.startsWith('/app/assets/')) {
    event.respondWith(
      caches.open(ASSETS).then(async (cache) => {
        const hit = await cache.match(req)
        if (hit) return hit
        const res = await fetch(req)
        if (res.ok) cache.put(req, res.clone())
        return res
      }),
    )
    return
  }

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) caches.open(SHELL).then((c) => c.put('/', res.clone()))
          return res
        })
        .catch(async () => (await caches.match('/')) || new Response(OFFLINE_HTML, { headers: { 'content-type': 'text/html; charset=utf-8' } })),
    )
  }
})
