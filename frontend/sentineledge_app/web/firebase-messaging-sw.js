/* global firebase */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: 'FIREBASE_WEB_API_KEY',
  appId: 'FIREBASE_WEB_APP_ID',
  messagingSenderId: 'FIREBASE_WEB_MESSAGING_SENDER_ID',
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