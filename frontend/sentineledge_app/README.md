# Erlang AI Vision App

Flutter frontend for the Erlang AI Vision web console and Android/iOS mobile clients.

See the full frontend setup guide:

- [Frontend setup](../../docs/frontend/frontend_setup.md)

## Auth

The app uses Firebase Auth for Google sign-in and email/password sign-in. After Firebase returns an ID token, the app calls the same FastAPI backend login endpoint:

```text
POST /api/v1/auth/firebase/login
Authorization: Bearer <firebase_id_token>
```

## Setup

Copy the example Firebase config and fill it with your Firebase Web app settings:

```powershell
Copy-Item config/firebase.example.json config/firebase.json
```

The local `config/firebase.json` file is ignored by Git. Keep backend secrets and Firebase Admin service account files out of the Flutter app. Email/password accounts must verify their email before the backend accepts the session.

## Push Notifications

The app registers FCM tokens with the backend after sign-in, refreshes them when Firebase rotates the token, deregisters on logout, and shows foreground alerts in-app. For web background push, fill `web/firebase-messaging-sw.js` with the same Firebase Web app values used in `config/firebase.json`, plus `FIREBASE_MESSAGING_VAPID_KEY`.

Run with the local config:

```powershell
flutter run -d web-server --web-port 8080 --dart-define-from-file=config/firebase.json
```

From the repository root, you can also start the backend and Flutter frontend together. This uses Flutter `web-server` by default and opens `http://localhost:8080` in your normal browser profile:

```powershell
.\scripts\start-dev.ps1
```

For local backend URLs:

```text
Web:     http://localhost:8000
Android: http://10.0.2.2:8000
iOS:     http://localhost:8000
```

Override the backend URL at build/run time:

```powershell
flutter run -d web-server --web-port 8080 --dart-define-from-file=config/firebase.json --dart-define=SENTINELEDGE_API_BASE_URL=http://localhost:8000
```

Run tests:

```powershell
flutter test
```

