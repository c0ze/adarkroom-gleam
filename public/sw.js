// A Dark Room — offline cache.
//
// Strategy:
//  - install: precache the shell — the page plus the bundle, stylesheets and
//    icons the build lists into PRECACHE — so the very first visit is
//    playable offline
//  - navigations: network first (so deploys land), cached shell offline
//  - /assets/ (hashed bundles) and /audio/ (immutable): cache first
//  - everything else same-origin (css, lang, manifest): stale-while-revalidate
//
// The build (vite.config.js) fills PRECACHE and stamps VERSION with a hash of
// the shell, so every release installs a fresh cache and drops the old one.
// Audio never changes under its name and is large, so it keeps a cache of its
// own that outlives releases.
const VERSION = "adr-dev";
const AUDIO = "adr-audio";
const PRECACHE = [];
const SHELL = "/";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(VERSION)
      .then((cache) => cache.addAll([SHELL, ...PRECACHE]))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k !== VERSION && k !== AUDIO)
            .map((k) => caches.delete(k)),
        ),
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
          // Only a real page may become the offline shell — never a 404.
          if (response.ok) {
            const copy = response.clone();
            caches.open(VERSION).then((cache) => cache.put(SHELL, copy));
          }
          return response;
        })
        .catch(() => caches.match(SHELL)),
    );
    return;
  }

  const audio = url.pathname.startsWith("/audio/");
  const immutable = audio || url.pathname.startsWith("/assets/");

  event.respondWith(
    caches.match(request).then((hit) => {
      // Immutable files never change under their names; skip the refetch.
      if (hit && immutable) {
        return hit;
      }
      const fetched = fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches
            .open(audio ? AUDIO : VERSION)
            .then((cache) => cache.put(request, copy));
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
