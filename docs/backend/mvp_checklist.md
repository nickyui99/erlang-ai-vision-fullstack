# Backend MVP Checklist

This checklist turns the backend plan into a practical implementation sequence.

## Milestone 1: Foundation

- [x] Create FastAPI backend structure.
- [x] Add environment configuration.
- [x] Add SQLite async database connection.
- [x] Enable SQLite foreign keys.
- [x] Add SQLAlchemy base model setup.
- [x] Add Alembic migrations.
- [x] Add `/healthz`.
- [x] Add `/readyz`.
- [x] Add `/api/v1/version`.
- [x] Add local `.env.example`.

## Milestone 2: Database

- [x] Implement `users`.
- [x] Implement `devices`.
- [x] Implement `agents`.
- [x] Implement `events`.
- [x] Implement `clips`.
- [x] Implement `recordings`.
- [x] Implement `alerts`.
- [x] Implement `tool_audit`.
- [x] Add ownership indexes.
- [x] Add event idempotency unique constraint.
- [x] Add clip idempotency unique constraint.

## Milestone 3: Auth

- [x] Add Firebase login endpoint.
- [x] Validate Firebase ID token.
- [x] Create or update local user.
- [x] Add backend session cookie.
- [x] Add `/api/v1/users/me`.
- [x] Add logout.
- [x] Add per-device edge token hashing.
- [x] Add edge-token authentication dependency.

## Milestone 4: Device and Agent Loop

- [x] Register device.
- [x] Return raw edge token once.
- [x] List user devices.
- [x] Update device metadata.
- [x] Accept edge heartbeat.
- [x] Create agent.
- [x] Compile edge config.
- [x] Arm/disarm agent.
- [x] Let edge pull active configs.

## Milestone 5: Event and Media Loop

- [x] Accept edge event submission.
- [x] Enforce `(device_id, idempotency_key)` uniqueness.
- [x] List user events.
- [x] Get event detail.
- [x] Register clip metadata.
- [x] Generate clip upload URL.
- [x] Mark clip upload complete.
- [x] Generate signed playback URL.
- [x] Register recording metadata.

## Milestone 6: Realtime

- [x] Add SSE endpoint.
- [x] Emit `event.created`.
- [x] Emit `clip.available`.
- [x] Emit `device.health_changed`.
- [x] Add SSE heartbeat.
- [x] Add reconnect behavior.

## Milestone 7: Edge Commands

- [x] Add edge WebSocket endpoint.
- [x] Authenticate edge WebSocket with edge token.
- [x] Track connected device sessions.
- [x] Relay pan command.
- [x] Relay snapshot command.
- [x] Store command results.
- [x] Audit tool actions.

## Milestone 8: Alerts

- [x] Add alert service interface. (`services/alert_service.py`)
- [x] Add first alert adapter. (Firebase Cloud Messaging push — `services/notification_service.py`)
- [x] Add alert deduplication. (one alert per `event_id` + channel via `uq_alerts_dedupe_key`)
- [x] Store alert result. (`alerts.status`: `sent` / `failed` / `no_recipients`)
- [x] Push alert status through SSE. (`alert.created` on the realtime bus)

Notes:
- Alerts fire on edge event submission for severity `>= ALERT_MIN_SEVERITY` (default `high`); toggle with `ALERTS_ENABLED`.
- Clients register an FCM token via `POST /api/v1/notifications/tokens` and remove it via `DELETE /api/v1/notifications/tokens/{token}`.
- FCM reuses the Firebase Admin SDK already configured for auth. Delivery is best-effort and never blocks event ingestion.
- Flutter client integration (requesting/registering the token, displaying notifications) is intentionally deferred.

## Milestone 8.5: Flutter Smart Camera UX

- [x] Make Cameras the primary frontend tab.
- [x] Replace the device list with smart-camera style cards.
- [x] Add a camera control screen with live/snapshot surface and quick action dock.
- [x] Add disabled placeholders for unsupported market-style controls: record, mute, talk, alarm, light, resolution, fullscreen.
- [x] Redesign PTZ as a circular controller.
- [x] Add UI-only favorite/preset chips and PTZ correction entry point.
- [x] Reframe agent assignment as camera Protection / Detection Rules.
- [x] Convert event review into a timeline-style camera app view.
- [x] Keep event IDs and stage output behind Technical details.
- [x] Add Flutter widget coverage for camera-first dashboard, camera controls, disabled placeholders, PTZ access, and snapshot display.

Remaining frontend work:
- [ ] Register FCM tokens from Flutter and display push notifications.
- [ ] Add backend + UI support for recording, audio mute/talk, alarm, fill light, resolution switching, and fullscreen live video.
- [ ] Persist camera presets/favorites and PTZ correction once backend APIs exist.
- [ ] Add real live stream rendering when an edge stream endpoint is available.
- [ ] Run mobile/emulator visual QA for the camera screens.

## Milestone 9: AI Verification and MCP

- [ ] Add Qwen client wrapper.
- [ ] Define verification schema.
- [ ] Validate or repair model output.
- [ ] Store `stage3_verdict`.
- [ ] Add MCP tool permissions.
- [ ] Add MCP tool audit logging.
- [ ] Enforce pan limits and high-risk tool rules.

## Milestone 10: Retention and Deployment

- [ ] Add retention config.
- [ ] Add cleanup job strategy.
- [ ] Block playback for deleted media.
- [ ] Delete expired OSS objects.
- [ ] Mark local recordings for edge deletion.
- [ ] Test SQLite-to-PostgreSQL migration compatibility.
- [ ] Prepare ECI deployment.
- [ ] Configure HTTPS ingress.
- [ ] Test REST, SSE, and WebSocket in deployed environment.

## MVP Done Definition

- [x] User can log in with Firebase Google sign-in.
- [x] User can register a device.
- [x] Edge can authenticate with device token.
- [x] User can create and arm an agent.
- [x] Edge can fetch active agent config.
- [x] Edge can submit an event.
- [x] Backend stores event and clip metadata.
- [x] User can list events.
- [x] User can request signed clip playback URL.
- [x] Backend can send a push alert (FCM) for a high-severity event.
- [x] Backend passes `/healthz` and `/readyz`.



