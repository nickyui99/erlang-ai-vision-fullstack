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

- [ ] Add Google OAuth start endpoint.
- [ ] Add Google OAuth callback endpoint.
- [ ] Validate OAuth `state`.
- [ ] Validate Google identity token.
- [ ] Create or update local user.
- [ ] Add backend session cookie.
- [ ] Add `/api/v1/users/me`.
- [ ] Add logout.
- [ ] Add per-device edge token hashing.
- [ ] Add edge-token authentication dependency.

## Milestone 4: Device and Agent Loop

- [ ] Register device.
- [ ] Return raw edge token once.
- [ ] List user devices.
- [ ] Update device metadata.
- [ ] Accept edge heartbeat.
- [ ] Create agent.
- [ ] Compile edge config.
- [ ] Arm/disarm agent.
- [ ] Let edge pull active configs.

## Milestone 5: Event and Media Loop

- [ ] Accept edge event submission.
- [ ] Enforce `(device_id, idempotency_key)` uniqueness.
- [ ] List user events.
- [ ] Get event detail.
- [ ] Register clip metadata.
- [ ] Generate clip upload URL.
- [ ] Mark clip upload complete.
- [ ] Generate signed playback URL.
- [ ] Register recording metadata.

## Milestone 6: Realtime

- [ ] Add SSE endpoint.
- [ ] Emit `event.created`.
- [ ] Emit `clip.available`.
- [ ] Emit `device.health_changed`.
- [ ] Add SSE heartbeat.
- [ ] Add reconnect behavior.

## Milestone 7: Edge Commands

- [ ] Add edge WebSocket endpoint.
- [ ] Authenticate edge WebSocket with edge token.
- [ ] Track connected device sessions.
- [ ] Relay pan command.
- [ ] Relay snapshot command.
- [ ] Store command results.
- [ ] Audit tool actions.

## Milestone 8: Alerts

- [ ] Add alert service interface.
- [ ] Add first alert adapter.
- [ ] Add alert deduplication.
- [ ] Store alert result.
- [ ] Push alert status through SSE.

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

- [ ] User can log in with Google OAuth.
- [ ] User can register a device.
- [ ] Edge can authenticate with device token.
- [ ] User can create and arm an agent.
- [ ] Edge can fetch active agent config.
- [ ] Edge can submit an event.
- [ ] Backend stores event and clip metadata.
- [ ] User can list events.
- [ ] User can request signed clip playback URL.
- [ ] Backend passes `/healthz` and `/readyz`.
