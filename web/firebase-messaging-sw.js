importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyBHbakAGVgamWXBBL_mFHCicOEhl61Z8FI",
  authDomain: "hastveda-notifications.firebaseapp.com",
  projectId: "hastveda-notifications",
  storageBucket: "hastveda-notifications.appfirebasestorage.app",
  messagingSenderId: "412267977624",
  appId: "1:412267977624:web:c85847f932d18ec69869ed"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(async (payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);

  // FCM automatically displays payloads that contain a notification object.
  // Data-only messages need an explicit browser notification.
  if (payload.notification) return;

  const data = payload.data || {};
  const title = String(data.title || 'HastVeda');
  const body = String(data.body || data.teaser || '');
  if (!body) {
    console.warn('[firebase-messaging-sw.js] Message has no displayable body.');
    return;
  }

  const options = {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { route: data.route || '/notifications', ...data },
    tag: data.ist_date ? 'hastveda-' + data.ist_date : 'hastveda-notification',
    renotify: false
  };

  await self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = event.notification.data?.route || '/notifications';
  const target = new URL(route, self.location.origin).href;

  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true
    });
    for (const client of windows) {
      if (client.url.startsWith(self.location.origin) && 'focus' in client) {
        await client.focus();
        if ('navigate' in client) await client.navigate(target);
        return;
      }
    }
    if (self.clients.openWindow) await self.clients.openWindow(target);
  })());
});