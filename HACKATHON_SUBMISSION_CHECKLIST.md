# Qwen Cloud Global Hackathon Submission Checklist

**Project:** Erlang AI Vision  
**Track:** Track 5 — EdgeAgent  
**Submission deadline:** July 20, 2026, 2:00 PM PDT

## Critical release blockers

- [x] Merge `codex/google-secret-manager` into `main`.
- [x] Switch the local Fullstack repository to `main`.
- [x] Synchronize local `main` with `origin/main`.
- [ ] Make `erlang-ai-vision-fullstack` public.
- [ ] Make `SentinelEdge_LaptopEdge` public.
- [ ] Make `SentinelEdge_IOT` public.
- [ ] Add an open-source license to LaptopEdge.
- [ ] Add an open-source license to IoT.
- [ ] Configure a public domain for the Alibaba Cloud deployment.
- [ ] Enable HTTPS with a valid TLS certificate.
- [ ] Verify Firebase permits the production domain.
- [ ] Test judge login from a fresh browser.
- [ ] Confirm production session cookies work over HTTPS.
- [ ] Create a judge account and document its credentials securely.
- [ ] Record a public demonstration video under three minutes.
- [ ] Upload the video to YouTube, Vimeo, or Youku.
- [ ] Add the video URL to Devpost.
- [ ] Create `docs/assets/demo.gif` or remove its broken README reference.

## README and repository presentation

- [ ] Add a “Qwen Cloud Global Hackathon” section near the top of the README.
- [ ] State the submission track: `Track 5 — EdgeAgent`.
- [ ] Add the live application URL.
- [ ] Add the public demo-video URL.
- [ ] Add judge testing instructions.
- [ ] Add links to all three repositories.
- [ ] Add a prominent architecture diagram.
- [ ] Add a direct Alibaba Cloud deployment-proof link.
- [ ] List the Qwen models used.
- [ ] Explain why Qwen is essential to the project.
- [ ] Document what was built after May 26, 2026.
- [ ] Add team-member information.
- [ ] Add a no-hardware demo walkthrough.
- [ ] Add a full physical-device setup walkthrough.
- [ ] Add expected results to every setup step.
- [ ] Add troubleshooting guidance.
- [ ] Configure the GitHub repository description.
- [ ] Configure the GitHub homepage with the live-demo URL.
- [ ] Add GitHub topics such as `qwen`, `edge-ai`, `iot`, `flutter`, `fastapi`, and `alibaba-cloud`.
- [ ] Confirm the MIT license appears in GitHub’s About section.

## Landing page and visual presentation

- [ ] Replace the visible “Image placeholder.”
- [ ] Replace the “Cloud architecture image placeholder.”
- [ ] Show the real architecture image.
- [ ] Add screenshots of natural-language agent creation.
- [ ] Show the compiled detector configuration.
- [ ] Show Qwen-VL verification output.
- [ ] Show audited Qwen tool calls.
- [ ] Show camera pan/tilt actions.
- [ ] Show realtime alerts.
- [ ] Show event playback.
- [ ] Test the landing page on desktop.
- [ ] Test the landing page on mobile.
- [ ] Check every public image and link.
- [ ] Remove remaining unfinished comments or placeholder copy.

## EdgeAgent judging criteria

- [ ] Clearly illustrate the flow: sensor → edge inference → Qwen Cloud → decision → physical action.
- [ ] Document which processing happens locally.
- [ ] Document which data is sent to Qwen Cloud.
- [ ] Explain how user privacy is protected.
- [ ] Measure edge-to-cloud event latency.
- [ ] Measure Qwen verification latency.
- [ ] Measure bandwidth reduction from local triage.
- [ ] Measure false-positive reduction.
- [ ] Estimate Qwen API cost per event.
- [ ] Demonstrate weak-network behavior.
- [ ] Demonstrate complete Qwen Cloud outage behavior.
- [ ] Demonstrate event queueing and reconnection.
- [ ] Demonstrate local operation without cloud access.
- [ ] Document camera-actuation safeguards.
- [ ] Add human confirmation for risky physical actions, if applicable.
- [ ] Compare the system with a cloud-only camera pipeline.

## Production security

- [ ] Reject startup when `SESSION_SECRET_KEY=change-me`.
- [ ] Reject production startup when required secrets are missing.
- [ ] Prevent silent mock-Qwen fallback in production.
- [ ] Clearly label demo/mock mode in the UI.
- [ ] Add rate limiting to authentication endpoints.
- [ ] Add rate limiting to chat endpoints.
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

## Tests and CI

- [x] Run backend tests: 101 passed, 1 skipped.
- [x] Run Flutter tests: 10 passed.
- [x] Run Flutter static analysis: no issues.
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

