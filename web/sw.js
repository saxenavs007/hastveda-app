'use strict';

// Replaced on each Render deploy so registration.update() sees a new worker.
const BUILD_ID = '__HASTVEDA_BUILD_ID__';
self.__hastvedaBuild = BUILD_ID;

self.addEventListener('install', function () {
  // New deployment takes over without waiting for every tab to close.
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches
      .keys()
      .then(function (keys) {
        return Promise.all(
          keys.map(function (key) {
            return caches.delete(key);
          }),
        );
      })
      .then(function () {
        return self.clients.claim();
      })
      .then(function () {
        return self.clients.matchAll({ type: 'window' });
      })
      .then(function (clients) {
        return Promise.all(
          clients.map(function (client) {
            if (client.url && 'navigate' in client) {
              return client.navigate(client.url);
            }
          }),
        );
      }),
  );
});
