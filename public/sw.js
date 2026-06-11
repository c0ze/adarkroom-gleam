// A Dark Room — offline cache.
//
// Strategy:
//  - navigations: network first (so deploys land), cached shell offline
//  - /assets/ (hashed bundles) and /audio/ (immutable): cache first
//  - everything else same-origin (css, img, manifest): stale-while-revalidate
//
// Bump the version to drop every old cache on the next visit.
const VERSION = "adr-v1";
const SHELL = "/";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(VERSION)
      .then((cache) => cache.addAll([SHELL, "/manifest.webmanifest"]))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== location.origin) {
    return;
  }

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(VERSION).then((cache) => cache.put(SHELL, copy));
          return response;
        })
        .catch(() => caches.match(SHELL)),
    );
    return;
  }

  const immutable =
    url.pathname.startsWith("/assets/") || url.pathname.startsWith("/audio/");

  event.respondWith(
    caches.match(request).then((hit) => {
      // Immutable files never change under their names; skip the refetch.
      if (hit && immutable) {
        return hit;
      }
      const fetched = fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(VERSION).then((cache) => cache.put(request, copy));
        }
        return response;
      });
      if (hit) {
        // Serve the cache now; let the refresh land for next time.
        fetched.catch(() => {});
        return hit;
      }
      return fetched;
    }),
  );
});
