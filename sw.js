/* Service worker — Auditoría de km
   - La app (HTML, config, íconos) se guarda para abrir sin conexión.
   - index.html y config.js se piden primero a la red, para tomar siempre la última versión.
   - Librerías y tipografías de CDN se sirven desde caché y se actualizan en segundo plano.
   - Las consultas a Supabase nunca se guardan acá: la app guarda su propia copia de los últimos datos.
   Al publicar cambios grandes, subí el número de VERSION. */
const VERSION = "auditoria-km-v1";
const SHELL = [
  "./", "./index.html", "./config.js", "./manifest.webmanifest",
  "./icons/icon-192.png", "./icons/icon-512.png", "./icons/apple-touch-icon.png", "./icons/favicon-64.png"
];
const CDN = ["cdn.jsdelivr.net", "cdnjs.cloudflare.com", "fonts.googleapis.com", "fonts.gstatic.com"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.hostname.endsWith("supabase.co")) return;          // datos: siempre a la red

  if (CDN.includes(url.hostname)) {                           // librerías: caché y actualización
    e.respondWith(caches.open(VERSION).then(async c => {
      const hit = await c.match(req);
      const net = fetch(req).then(r => { if (r.ok || r.type === "opaque") c.put(req, r.clone()); return r; }).catch(() => hit);
      return hit || net;
    }));
    return;
  }

  if (url.origin === self.location.origin) {                  // la app: red primero
    e.respondWith(
      fetch(req).then(r => {
        if (r.ok) { const copy = r.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
        return r;
      }).catch(async () =>
        (await caches.match(req, { ignoreSearch: true })) ||
        (req.mode === "navigate" ? caches.match("./index.html") : Response.error())
      )
    );
  }
});
