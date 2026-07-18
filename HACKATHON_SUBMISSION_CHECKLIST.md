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
- [ ] Configure a public domain for the Alibaba Cloud deployment.
- [ ] Enable HTTPS with a valid TLS certificate.
- [ ] Verify Firebase permits the production domain.
- [ ] Test judge login from a fresh browser.
- [ ] Confirm production session cookies work over HTTPS.
- [ ] Create a judge account and document its credentials securely.
- [ ] Record a public demonstration video under three minutes.
- [ ] Upload the video to YouTube, Vimeo, or Youku.
- [ ] Add the video URL to Devpost.

## Judge-demo updates - July 17

- [x] Add a Qwen-based no-hardware judge camera loop using pre-extracted JPEG frames.
- [x] Limit judge-demo inference: send the first camera frame to Qwen after 4 seconds, then at most once per minute.
- [x] Disable Qwen hidden thinking for the judge demo's structured vision response.
- [x] Refresh local Baby-camera demo frames from `data/demo_videos/baby.mp4`.
- [ ] Deploy the refreshed Baby-camera frames and judge-demo timing configuration.
- [ ] Verify in a fresh browser that a judge camera produces a Qwen event after the first 4-second sample.

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
- [x] Add the live application URL (currently the EIP `http://47.250.155.149`; swap in the domain + HTTPS link once configured).
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
- [ ] Confirm the MIT license appears in GitHub’s About section.

## Landing page and visual presentation

- [ ] Replace the visible “Image placeholder.”
- [ ] Replace the “Cloud architecture image placeholder.”
- [x] Show the real architecture image.
- [ ] Add screenshots of natural-language agent creation.
- [ ] Show the compiled detector configuration.
- [x] Show Qwen-VL verification output.
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

- [ ] Reject startup when `SESSION_SECRET_KEY=change-me`.
- [ ] Reject production startup when required secrets are missing.
- [ ] Prevent silent mock-Qwen fallback in production.
- [ ] Clearly label demo/mock mode in the UI.
- [ ] Add rate limiting to authentication endpoints.
- [x] Add rate limiting to chat endpoints (per-account daily message cap, July 15; burst/per-second limiting can still be added at a proxy if needed).
- [ ] Add rate limiting to Qwen verification endpoints.
- [ ] Add request-size limits for images and media.
- [ ] Confirm CORS permits only required production origins.
- [ ] Confirm Firebase authorized domains are restricted correctly.
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

- [ ] Add a production readiness endpoint.
- [ ] Report Qwen configuration status without exposing secrets.
- [ ] Report database connectivity.
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
- [x] Run Flutter static analysis: no issues (re-verified July 15 after assignment-state changes).
- [ ] Fix the two `aiosqlite` teardown warnings.
- [ ] Add Qwen timeout tests.
- [ ] Add Qwen HTTP 429 tests.
- [ ] Add invalid Qwen JSON tests.
- [ ] Add malformed tool-call tests.
- [ ] Add empty model-response tests.
- [ ] Add retry/backoff tests.
- [ ] Add frontend AI chat-screen widget tests.
- [ ] Add production configuration validation tests.
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

