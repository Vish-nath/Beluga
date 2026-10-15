const CACHE_NAME = "beluga-health-v3";
const APP_ROOT = new URL("./", self.location).pathname;
const APP_SHELL = ["", "styles.css", "app.js", "mark.svg", "care-orbit.svg", "manifest.webmanifest"].map(
  (path) => new URL(path, new URL("./", self.location)).pathname
);

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const requestUrl = new URL(event.request.url);
  if (event.request.method !== "GET" || requestUrl.origin !== self.location.origin || requestUrl.pathname.startsWith("/api/")) return;
  event.respondWith(fetch(event.request).catch(() => caches.match(event.request).then((cached) => cached || caches.match(APP_ROOT))));
});
