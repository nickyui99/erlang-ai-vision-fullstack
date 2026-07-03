# Backend MVP Checklist

This checklist turns the backend plan into a practical implementation sequence.

## Next up (read me first)

Backend Milestones 1–9 are done. The gap to a hands-free, end-to-end demo:

1. **Edge detection / agent tier — the biggest gap.** Nothing auto-generates
   events from video yet. Arming an agent stores a compiled config, but no
   component runs detectors on frames and POSTs to `/api/v1/edge/events`.
   `SentinelEdge_IOT/receiver/edge_bridge.py` only forwards video + commands and
   *logs* the pulled config — it never detects.
   - **Workaround now:** `python scripts/simulate_event.py` posts events the way
     that tier would, which drives the real AI verification + frontend trail.
   - **To build:** an edge loop that pulls active configs, runs a Stage 1/2
     detector (e.g. a person model) on frames, and POSTs matched events (with
     debounce + idempotency).
2. **Rule compiler is a stub.** `_compile_agent_rule` maps *every* rule to
   `{detectors:[person], min_confidence:0.75}` — it ignores the rule text. Make
   it translate the rule into real detector classes/thresholds.
3. **Milestone 10** - cleanup execution, OSS object deletion, local recording
   deletion signaling, SQLite to PostgreSQL verification, and deployed ECI smoke
   testing. The cloud RDS instance, retention settings, soft-delete playback
   blocking, OSS signed URLs, and the ECI deployment script are already in place.
4. **Frontend** - Milestone 8.5 is functionally complete except mobile/emulator visual QA.

Helper scripts: `scripts/simulate_event.py` (fake events), `scripts/verify_smoke.py`
(live Qwen check), `scripts/seed_local_device.py` (local device + token),
`scripts/stream_simulator.py` (fake video), `scripts/migrate_sqlite_to_rds.py`
(SQLite to ApsaraDB RDS PostgreSQL copy/check), and
`scripts/deployment/backend.ps1` (Docker build, smoke test, optional ACR/ECI
deploy).

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
- [x] Add market-style controls for record, mute, talk, alarm, light, resolution, and fullscreen.
- [x] Redesign PTZ as a circular controller.
- [x] Persist camera favorites, presets, and PTZ correction from the camera control screen.
- [x] Reframe agent assignment as camera Protection / Detection Rules.
- [x] Convert event review into a timeline-style camera app view.
- [x] Keep event IDs and stage output behind Technical details.
- [x] Add Flutter widget coverage for camera-first dashboard, camera controls, active command controls, PTZ access, and snapshot display.

Remaining frontend work:
- [x] Register FCM tokens from Flutter and display push notifications.
- [x] Add backend + UI support for recording, audio mute/talk, alarm, fill light, resolution switching, and fullscreen live video.
- [x] Persist camera presets/favorites and PTZ correction via `PUT /api/v1/devices/{device_id}`.
- [x] Add real live stream rendering through signed MJPEG/latest-frame backend endpoints.
- [ ] Run mobile/emulator visual QA for the camera screens.

Notes:
- Flutter push registration uses `firebase_messaging`, registers tokens with
  `POST /api/v1/notifications/tokens`, deregisters on logout, listens for token
  refresh, and shows foreground FCM alerts with an in-app snackbar.
- Web background push requires replacing the placeholders in
  `web/firebase-messaging-sw.js` with the deployed Firebase Web app values; native
  mobile display still needs emulator/device QA.
- Market-style controls relay through `POST /api/v1/devices/{device_id}/control`
  and audited edge messages (`command.recording`, `command.audio_mute`,
  `command.talk`, `command.alarm`, `command.fill_light`, `command.resolution`).
  LaptopEdge/firmware still need to implement those command handlers for real device effects.
- Camera favorites, presets, and PTZ correction are persisted on the device record and returned by device list/detail endpoints.

## Milestone 9: AI Verification and MCP

Plan: [milestone9_plan.md](milestone9_plan.md). Built in sub-milestones 9A → 9B → 9C (all done).

9A — Qwen verification core (done):
- [x] Add Qwen client wrapper. (`services/qwen_client.py`: real `QwenClient` + offline `MockQwenClient`)
- [x] Define verification schema. (`schemas/verification.py`)
- [x] Validate or repair model output. (`verification_service._extract_json` / `_normalize` + one repair re-ask, else `degraded`)
- [x] Store `stage3_verdict`. (background task off event ingestion; emits `event.verified`, re-evaluates alerting)

9B/9C — MCP tools + agentic loop (done):
- [x] Add MCP tool permissions. (`mcp/permissions.py`: autonomy table; high-risk tools denied)
- [x] Add MCP tool audit logging. (`mcp/tools.py`: every call → `tool_audit`, `called_by="agent"`, `event_id`)
- [x] Enforce pan limits and high-risk tool rules. (per-event `PanRateLimiter` + 0–180 clamp; verification runs a bounded tool-calling loop via `chat()`)

Notes:
- Verification is **opt-in** (`VERIFICATION_ENABLED`, default `false`) and triggers for events at or above `VERIFY_MIN_SEVERITY` (default `high`). Default ingestion/alert behaviour is unchanged when off.
- Without `QWEN_API_KEY` (or under `APP_ENV=test`) the service uses a deterministic mock verdict so the pipeline runs offline.
- Tests: `tests/test_milestone9_verification.py` (run alone, per the milestone-test convention).

## Milestone 10: Retention and Deployment

- [x] Add retention config. (`MEDIA_RETENTION_DAYS`, `DAILY_RECORDING_RETENTION_HOURS`)
- [ ] Add cleanup job strategy.
- [x] Block playback for deleted media. (`clips.py`, `recordings.py`, and local media token paths)
- [ ] Delete expired OSS objects.
- [ ] Mark local recordings for edge deletion.
- [x] ApsaraDB RDS PostgreSQL instance is provisioned in cloud.
- [ ] Run and verify SQLite-to-PostgreSQL migration/smoke tests against the cloud RDS target.
- [x] Prepare ECI deployment. (`scripts/deployment/backend.ps1`)
- [ ] Configure production HTTPS ingress.
- [ ] Test REST, SSE, and WebSocket in deployed environment.
- [x] Add real OSS signed upload/playback/download URL generation when OSS settings are configured.

Notes:
- `MediaUrlService` now signs Alibaba OSS URLs directly when
  `ALICLOUD_OSS_ENDPOINT`, `ALICLOUD_OSS_BUCKET`, `ALIBABA_CLOUD_ACCESS_KEY_ID`,
  and `ALIBABA_CLOUD_ACCESS_KEY_SECRET` are set. Local/offline tests still use
  `placeholder://` URLs intentionally.
- `scripts/deployment/backend.ps1 -Deploy` can build, push to ACR, and create
  the ECI container group with a Caddy sidecar. The current script exposes HTTP
  on the standing EIP; production HTTPS/ALB validation remains open.
- The cloud RDS target already exists. `scripts/migrate_sqlite_to_rds.py` is the
  one-shot SQLite to RDS copy/verification helper; the migration validation item
  stays open until it has been run against that target and smoke tests pass.

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
- [ ] Backend is deployed to Alibaba Cloud ECI and passes deployed REST/SSE/WebSocket smoke tests.




