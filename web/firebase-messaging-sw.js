importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// Values are substituted by build.sh for the selected environment.
firebase.initializeApp({
  apiKey: "__FIREBASE_API_KEY__",
  authDomain: "__FIREBASE_AUTH_DOMAIN__",
  projectId: "__FIREBASE_PROJECT_ID__",
  storageBucket: "__FIREBASE_STORAGE_BUCKET__",
  messagingSenderId: "__FIREBASE_MESSAGING_SENDER_ID__",
  appId: "__FIREBASE_APP_ID__"
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