// Service worker de "MonAvi Caja" (PWA del comercio, scope /canjear).
// Solo hace la app instalable y muestra un aviso si no hay internet: los
// canjes SIEMPRE se validan en linea (nunca se guardan ni se confirman
// sin conexion).
const CACHE = "monavi-caja-v1";
const OFFLINE_URL = "/canjear-offline.html";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      cache.addAll([OFFLINE_URL, "/caja/icon-192.png", "/caja/icon-512.png"]),
    ),
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))),
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  if (request.mode === "navigate") {
    event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL)));
    return;
  }
  const url = new URL(request.url);
  if (url.pathname.startsWith("/caja/")) {
    event.respondWith(caches.match(request).then((hit) => hit || fetch(request)));
  }
});
