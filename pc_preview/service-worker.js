const CACHE_NAME = "motiva-bricks-v0.1.0";
const APP_ASSETS = [
  "./",
  "./index.html",
  "./styles.css",
  "./manifest.webmanifest",
  "./src/main.js",
  "./src/game.js",
  "./src/audio.js",
  "./src/ad-bridge.js",
  "./src/level-loader.js",
  "./src/level-generator.js",
  "./src/utils.js",
  "./config/game-config.json",
  "./levels/index.json",
  "./levels/level-01-neon-gates.json",
  "./levels/level-02-core-spiral.json",
  "./levels/level-03-pixel-guardian.json",
  "./levels/level-04-circuit-maze.json",
  "./levels/level-05-star-reactor.json",
  "./assets/icons/icon-192.png",
  "./assets/icons/icon-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_ASSETS)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
    ))
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  const requestUrl = new URL(event.request.url);
  const isRemoteLevels = requestUrl.origin !== self.location.origin;

  if (isRemoteLevels) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const clone = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
