'use strict';

// Replaced on each Render deploy so registration.update() sees a new worker.
const BUILD_ID = '__HASTVEDA_BUILD_ID__';
self.__hastvedaBuild = BUILD_ID;

self.addEventListener('install', function () {
  // Activate the newest worker promptly so installed PWA clients can update.
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  // Do not delete every cache on the origin: other app resources or future
  // caches may be unrelated. Claim clients and let the page reload once when
  // the new worker takes control.
  event.waitUntil(self.clients.claim());
});
