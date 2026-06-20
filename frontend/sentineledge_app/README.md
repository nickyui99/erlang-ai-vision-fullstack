# SentinelEdge App

Flutter frontend for SentinelEdge web and mobile.

## Auth

The app uses Firebase Auth for Google sign-in. After Firebase returns an ID token, the app calls the FastAPI backend:

```text
POST /api/v1/auth/firebase/login
Authorization: Bearer <firebase_id_token>
```

## Setup

Copy the example Firebase config and fill it with your Firebase web app settings:

```powershell
Copy-Item config/firebase.example.json config/firebase.json
```

Run with the local config:

```powershell
flutter run -d chrome --dart-define-from-file=config/firebase.json
```

For local backend URLs:

```text
Web:     http://localhost:8000
Android: http://10.0.2.2:8000
iOS:     http://localhost:8000
```

Override the backend URL at build/run time:

```powershell
flutter run --dart-define=SENTINELEDGE_API_BASE_URL=http://localhost:8000
```

Run tests:

```powershell
flutter test
```
