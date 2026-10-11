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

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
});