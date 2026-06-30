# Frontend Setup

The SentinelEdge frontend is a Flutter app at `frontend/sentineledge_app`.

## Current Scope

The app currently covers the authenticated smart-camera console flow:

- Firebase Google sign-in in Flutter.
- Firebase ID token retrieval from the signed-in user.
- Backend login through `POST /api/v1/auth/firebase/login`.
- Display of the backend user profile returned by SentinelEdge.
- Logout through Firebase Auth and the backend session.
- Camera-first dashboard with smart-camera style device cards.
- Device registration and one-time edge-token display.
- Agent creation and camera Protection / Detection Rule toggles.
- Event timeline review with clip playback URL requests.
- Realtime status updates through the backend event stream.
- Edge controls for pan, tilt, and snapshot commands.
- Market-style camera affordances shown as disabled placeholders where backend APIs do not exist yet.

Remaining frontend work:

- Register FCM tokens from Flutter and display push notifications.
- Add real backend + UI support for recording, audio mute/talk, alarm, fill light, resolution switching, fullscreen live video, presets, and PTZ correction.
- Keep live stream rendering polished across MJPEG and latest-frame polling modes.
- Run mobile/emulator visual QA for the camera screens.

## Firebase Client Config

Flutter reads Firebase client settings from Dart compile-time defines. The real local config file is intentionally ignored by Git.

Copy the example:

```powershell
cd frontend\sentineledge_app
Copy-Item config\firebase.example.json config\firebase.json
```

Fill `config/firebase.json` with the Firebase Web app config from Firebase Console:

```json
{
  "FIREBASE_WEB_API_KEY": "your-web-api-key",
  "FIREBASE_WEB_APP_ID": "your-web-app-id",
  "FIREBASE_WEB_MESSAGING_SENDER_ID": "your-sender-id",
  "FIREBASE_PROJECT_ID": "sentineledge-e069b",
  "FIREBASE_AUTH_DOMAIN": "sentineledge-e069b.firebaseapp.com"
}
```

These Firebase client values are not backend secrets, but keeping the local file ignored avoids committing environment-specific config.

Never put Firebase Admin service account JSON, database passwords, session secrets, or backend credentials in Flutter files.

## Run Locally

Start the backend first from the repository root:

```powershell
$env:PYTHONPATH="backend"
uvicorn app.main:app --reload
```

Run the full stack from the repository root:

```powershell
.\scripts\start-dev.ps1
```

The script runs Flutter as a web server at `http://localhost:8080` and opens that URL in your normal browser profile. That is preferred for local Firebase Google sign-in because it avoids creating a fresh browser profile on every run.

You can also run Flutter directly from the app directory:

```powershell
cd frontend\sentineledge_app
flutter run -d web-server --web-port 8080 --dart-define-from-file=config/firebase.json
```

The default web backend URL is:

```text
http://localhost:8000
```

Override it when needed:

```powershell
flutter run -d web-server --web-port 8080 --dart-define-from-file=config/firebase.json --dart-define=SENTINELEDGE_API_BASE_URL=http://localhost:8000
```

## Platform Backend URLs

Default backend URLs in the Flutter app:

| Platform | URL |
|---|---|
| Web | `http://localhost:8000` |
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator | `http://localhost:8000` |

## Auth Request

After Firebase sign-in, the app sends:

```http
POST /api/v1/auth/firebase/login
Authorization: Bearer <firebase_id_token>
```

The backend verifies the token with Firebase Admin SDK, creates or updates the local user, and sets the SentinelEdge session cookie.

## Validation

Run Flutter analysis:

```powershell
flutter analyze
```

Run Flutter tests:

```powershell
flutter test
```

Manual validation:

1. Backend is running on `http://localhost:8000`.
2. Flutter starts with `--dart-define-from-file=config/firebase.json`.
3. Google sign-in succeeds.
4. The app shows the backend user profile.
5. Backend logs show `POST /api/v1/auth/firebase/login` returning success.



