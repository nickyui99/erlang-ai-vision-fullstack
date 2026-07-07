/* global firebase */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

// Firebase Web client config. These values are public (they already ship in the
// web bundle), so it is safe to hard-code them in this static service worker.
const firebaseConfig = {
  apiKey: 'AIzaSyBrsT04CGk8w3fc3v6QoPwdUxfIicRKH98',
  appId: '1:214249593640:web:732744ed546e8258cb0e1d',
  messagingSenderId: '214249593640',
  projectId: 'sentineledge-e069b',
  authDomain: 'sentineledge-e069b.firebaseapp.com',
};

if (!firebaseConfig.apiKey.startsWith('FIREBASE_')) {
  firebase.initializeApp(firebaseConfig);
  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const notification = payload.notification || {};
    const title = notification.title || 'Security alert';
    const options = {
      body:
        notification.body ||
        payload.data?.summary ||
        'A camera event needs review.',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-maskable-192.png',
      data: payload.data || {},
    };

    self.registration.showNotification(title, options);
  });
}