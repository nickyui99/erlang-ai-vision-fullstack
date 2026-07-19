# Qwen Cloud Global Hackathon Submission Checklist

**Project:** Erlang AI Vision  
**Track:** Track 5 — EdgeAgent  
**Submission deadline:** July 20, 2026, 2:00 PM PDT

## Critical release blockers

- [x] Merge `codex/google-secret-manager` into `main`.
- [x] Switch the local Fullstack repository to `main`.
- [x] Synchronize local `main` with `origin/main`.
- [x] Make `erlang-ai-vision-fullstack` public (verified anonymously, July 15).
- [ ] Make `SentinelEdge_LaptopEdge` public (still returns 404 to a logged-out request as of July 15).
- [ ] Make `SentinelEdge_IOT` public (still returns 404 to a logged-out request as of July 15).
- [x] Add an open-source license to LaptopEdge (committed and pushed).
- [x] Add an open-source license to IoT.
- [x] Add an open-source license to Fullstack (committed and pushed).
- [x] Configure the public Alibaba Cloud domain (`https://erlang-vision.duckdns.org`).
- [x] Enable HTTPS with a valid TLS certificate (Caddy on the ECI public origin).
- [ ] Verify Firebase permits the production domain.
- [ ] Test judge login from a fresh browser.
- [ ] Confirm production session cookies work over HTTPS.
- [ ] Create a judge account and document its credentials securely.
- [ ] Record a public demonstration video under three minutes.
- [x] Publish the public judge APK release ([`v1.0.0-judge`](https://github.com/nickyui99/erlang-ai-vision-fullstack/releases/tag/v1.0.0-judge)); verify its live-backend URL and downloadable APK while signed out.
- [ ] Upload the video to YouTube, Vimeo, or Youku.
- [ ] Add the video URL to Devpost.

## Judge-demo updates - July 17

- [x] Add a Qwen-based no-hardware judge camera loop using pre-extracted JPEG frames.
- [x] Limit judge-demo inference: send the first camera frame to Qwen after 4 seconds, then at most once per minute.
- [x] Disable Qwen hidden thinking for the judge demo's structured vision response.
- [x] Refresh local Baby-camera demo frames from `data/demo_videos/baby.mp4`.
- [x] Deploy the refreshed judge-camera frames and judge-demo timing configuration.
- [x] Enable the production judge-demo simulator; bundled frames now publish to `dev_judge_` cameras on demand.
- [ ] Verify in a fresh browser that a judge camera produces a Qwen event after the first 4-second sample.

## Production updates — July 18–19

- [x] Deploy the Flutter web app and FastAPI backend on one HTTPS origin (`https://erlang-vision.duckdns.org`), with Caddy routing `/api` to FastAPI and the app to OSS over Alibaba's internal endpoint.
- [x] Keep the deployment on one ECI + standing EIP; no CDN or second API instance is required for the current demo.
- [x] Serve the release web bundle with Brotli compression and local Flutter WebAssembly renderer assets to improve first-load performance.
- [x] Reduce Flutter startup dependencies and defer dashboard loading work; Flutter analysis passes after the optimisation work.
- [x] Fix judge live-view frame availability by enabling the server-side demo simulator in the deployed ECI configuration.
- [x] Add a root app messenger so foreground FCM messages show the floating Flutter in-app alert after login or session restore.
- [x] Deduplicate matching FCM and realtime alerts, so one event does not produce multiple in-app banners.
- [x] Enable alerts from `low` upward in production; low, medium, high, and critical events now qualify for the alert flow.
- [x] Verify the deployed backend health endpoint and the cloud ECI alert-threshold configuration without exposing secrets.
- [x] Verify the live frontend and backend readiness endpoint return HTTP 200 after the July 19 deployment.
- [x] Update the production Content Security Policy to permit Flutter CanvasKit and Google Fonts (`gstatic`/`fonts.gstatic.com`); text and WebAssembly renderer assets can load.
- [ ] Add `erlang-vision.duckdns.org` to Firebase Authentication's authorized domains, then test Google sign-in from a fresh browser.
- [x] Preserve the valid TLS certificate on `erlang-vision.duckdns.org` during subsequent deployments.
- [x] Scan the pending source changes for credential signatures before pushing to `main`; local `.env` remains ignored.
- [ ] Verify foreground in-app alerts and low/medium alert delivery from a fresh browser session.
- [ ] Complete the LaptopEdge simulator/cloud run: wait for `device listener ready` and `backend websocket connected`, then verify frames and events arrive in the cloud console.

## Shipped July 15 (document in README, Devpost, and the demo video)

- [x] Fix the silent no-alerts bug: `/edge/agents/active` now sends `compiled_prompt`/`nl_rule` so edge triage judges the user's actual rule.
- [x] Fix edge triage verdict parsing (qwen3.5:0.8b's `"trigger"` key alias and two non-JSON reply shapes) — events now escalate end-to-end.
- [x] Make the app's record button work end-to-end (bridge `command.recording` → LiveRecorder → `POST /edge/recordings`).
- [x] Preserve event/alert/clip history when an agent is disabled on a camera (unassign disarms the sub-agent instead of deleting it; re-assign re-arms the same row).
- [x] Instant agent arm/disarm: backend nudges the bridge (`command.refresh_agents`) to re-poll immediately instead of waiting the 30 s config poll.
- [x] Fix in-app clip playback: recorders now encode H.264 (`avc1`) instead of browser-unplayable `mp4v`, with fallback where no H.264 encoder exists.
- [x] Expose the platform's tools as an MCP server (`/api/v1/mcp`, 12 user-scoped tools, signed bearer tokens, audited, permission-tabled).
- [x] Make the Erlang AI Agent chat agentic: it connects to the MCP server as an MCP client and can control cameras, create/arm/disarm agents, query events, and fetch clips/recordings live (falls back to text-only chat if MCP is down).
- [x] Extract shared agent lifecycle logic into `agent_service` (REST API and MCP tools run identical code).
- [x] Mention the MCP server in the README (features bullet + "MCP tool server" section with tools, auth, and guardrails).
- [x] Rate-limit the agentic chat: per-account daily message cap (`CHAT_DAILY_MESSAGE_LIMIT`, default 50/day, HTTP 429 `chat_daily_limit_reached`, 0 disables) on top of the existing per-turn tool budget (`QWEN_MAX_TOOL_TURNS`).

## README and repository presentation

- [x] Add a “Qwen Cloud Global Hackathon” section near the top of the README.
- [x] State the submission track: `Track 5 — EdgeAgent`.
- [x] Replace the README live-application placeholder with `https://erlang-vision.duckdns.org`.
- [ ] Add the public demo-video URL (placeholder row is in the README table — record the video first).
- [x] Add judge testing instructions.
- [x] Add links to all three repositories (hackathon table + tier table).
- [x] Add a prominent architecture diagram.
- [ ] Add a direct Alibaba Cloud deployment-proof link.
- [x] List the Qwen models used.
- [x] Explain why Qwen is essential to the project.
- [x] Document what was built after May 26, 2026.
- [x] Add team-member information.
- [x] Add a no-hardware demo walkthrough.
- [x] Add a full physical-device setup walkthrough.
- [ ] Add expected results to every setup step.
- [x] Add troubleshooting guidance.
- [ ] Configure the GitHub repository description.
- [ ] Configure the GitHub homepage with the live-demo URL.
- [ ] Add GitHub topics such as `qwen`, `edge-ai`, `iot`, `flutter`, `fastapi`, and `alibaba-cloud`.
- [X] Confirm the MIT license appears in GitHub’s About section.

## Landing page and visual presentation

- [ ] Replace the visible “Image placeholder.”
- [ ] Replace the “Cloud architecture image placeholder.”
- [x] Show the real architecture image.
- [ ] Add screenshots of natural-language agent creation.
- [ ] Show the compiled detector configuration.
- [x] Show Qwen-Plus verification output.
- [x] Show audited Qwen tool calls.
- [x] Show camera pan/tilt actions.
- [ ] Show realtime alerts.
- [ ] Show event playback.
- [ ] Test the landing page on desktop.
- [ ] Test the landing page on mobile.
- [ ] Check every public image and link.
- [ ] Remove remaining unfinished comments or placeholder copy.

## EdgeAgent judging criteria

- [ ] Clearly illustrate the flow: sensor → edge inference → Qwen Cloud → decision → physical action.
- [x] Document which processing happens locally.
- [x] Document which data is sent to Qwen Cloud.
- [x] Explain how user privacy is protected.
- [ ] Measure edge-to-cloud event latency.
- [ ] Measure Qwen verification latency.
- [ ] Measure bandwidth reduction from local triage.
- [ ] Measure false-positive reduction.
- [ ] Estimate Qwen API cost per event.
- [ ] Demonstrate weak-network behavior.
- [ ] Demonstrate complete Qwen Cloud outage behavior.
- [ ] Demonstrate event queueing and reconnection.
- [ ] Demonstrate local operation without cloud access.
- [x] Document camera-actuation safeguards.
- [ ] Add human confirmation for risky physical actions, if applicable (more relevant since July 15: the chat agent can now pan/tilt cameras and arm/disarm agents via MCP tools — currently guarded by clamps, rate limits, and audit rather than confirmation).
- [ ] Compare the system with a cloud-only camera pipeline.

## Production security

- [x] Reject startup when `SESSION_SECRET_KEY=change-me`.
- [x] Reject production startup when required secrets are missing.
- [x] Prevent silent mock-Qwen fallback in production.
- [ ] Clearly label demo/mock mode in the UI.
- [x] Add production rate limiting to Firebase login (10 requests/minute per forwarded client IP) and edge ingestion (240 requests/minute per forwarded client IP).
- [x] Add rate limiting to chat endpoints (per-account daily message cap, July 15; burst/per-second limiting can still be added at a proxy if needed).
- [x] Add rate limiting to Qwen verification endpoints.
- [x] Add request-size limits for HTTP API bodies; media bytes upload directly to OSS through signed URLs.
- [x] Confirm CORS permits only the required production origin in the ECI deployment configuration.
- [ ] Confirm Firebase authorized domains include only the active production hostname and required development hosts.
- [ ] Confirm judge credentials have limited permissions.
- [ ] Confirm demo accounts cannot access real devices.
- [ ] Rotate credentials before making repositories public.
- [ ] Run a final secret scan across Git history.
- [ ] Review Firebase rules.
- [ ] Review Alibaba OSS bucket permissions.
- [ ] Review RDS network access and database permissions.
- [ ] Review Google Secret Manager IAM permissions.
- [ ] Confirm logs never expose tokens or credentials.

## Reliability and observability

- [x] Add production health and readiness endpoints (`/healthz` and `/readyz`).
- [ ] Report Qwen configuration status without exposing secrets.
- [x] Report database connectivity through `/readyz`.
- [x] Restrict RDS access to the ECI private network; remove public database CIDR access.
- [x] Disable production FastAPI OpenAPI/docs routes and block `/docs` and `/openapi.json` at the proxy.
- [x] Apply production browser security headers (HSTS, CSP, anti-framing, content-type, referrer, and permissions policies).
- [x] Invalidate cached edge tokens immediately when a device token is rotated.
- [ ] Report Alibaba OSS connectivity.
- [ ] Report Firebase connectivity.
- [ ] Track Qwen request latency.
- [ ] Track Qwen failure and timeout rates.
- [ ] Track token usage.
- [ ] Track estimated Qwen cost.
- [ ] Track edge-device connection health.
- [ ] Track event-processing latency.
- [ ] Track tool-call success rate.
- [ ] Propagate request IDs between edge and cloud.
- [ ] Add retry and exponential backoff for Qwen rate limits.
- [ ] Add graceful handling for malformed Qwen responses.
- [ ] Add graceful handling for unavailable OSS or RDS services.

## IoT firmware verification

- [x] Build the XIAO ESP32-S3 target: pio run -e xiao_s3.
- [x] Build the USB-CDC target: pio run -e usb_stream.
- [x] Build the Wokwi target: pio run -e wokwi.
- [x] Reconcile IoT protocol, wiring, simulation, USB, and current-system documentation.
- [ ] Complete final dual-servo hardware-in-loop validation.

## Tests and CI

- [x] Run backend tests: 143 passed, 1 skipped (July 15; includes MCP server, agentic chat, recording, and history-preservation tests).
- [x] Run edge (LaptopEdge) tests: triage 11/11 with the real model; all bridge assertions incl. recording + refresh-nudge.
- [x] Run Flutter tests: 10 passed.
- [x] Run Flutter static analysis: no issues (re-verified July 19 after the in-app alert work).
- [ ] Fix the two `aiosqlite` teardown warnings.
- [ ] Add Qwen timeout tests.
- [ ] Add Qwen HTTP 429 tests.
- [ ] Add invalid Qwen JSON tests.
- [ ] Add malformed tool-call tests.
- [ ] Add empty model-response tests.
- [ ] Add retry/backoff tests.
- [ ] Add frontend AI chat-screen widget tests.
- [x] Add production configuration validation tests.
- [ ] Add an end-to-end judge smoke test.
- [ ] Run the smoke test against the Alibaba deployment.
- [ ] Add backend test execution to CI.
- [ ] Add Flutter tests and analysis to CI.
- [ ] Add Docker build verification to CI.
- [ ] Add dependency vulnerability scanning.
- [ ] Add secret scanning.
- [ ] Add README link checking.
- [ ] Require CI success before merging to `main`.

## Devpost submission package

- [ ] Complete every required Devpost field.
- [ ] Select `Track 5 — EdgeAgent`.
- [ ] Provide the public source repository.
- [ ] Provide a clear feature and functionality description.
- [ ] Provide the Alibaba Cloud deployment-proof link.
- [ ] Upload the architecture diagram.
- [ ] Provide the public demo-video URL.
- [ ] Provide the live-demo URL.
- [ ] Provide judge credentials and testing instructions.
- [ ] Confirm the video is shorter than three minutes.
- [ ] Confirm the video shows the physical device functioning.
- [ ] Remove unauthorized trademarks and copyrighted music.
- [ ] Confirm all submission materials are in English.
- [ ] Explain development completed during the hackathon period.
- [ ] Publish a build-journey blog or social post for the bonus prize.
- [ ] Add the blog/social URL to Devpost.
- [ ] Test every submitted link while logged out.
- [ ] Run the entire judge journey in a fresh browser.
- [ ] Keep the application available through the end of judging.
- [ ] Submit before July 20, 2026, 2:00 PM PDT.

