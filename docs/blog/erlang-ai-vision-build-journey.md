# From Passive CCTV to Intelligent Surveillance Agents: Building Erlang AI Vision with Qwen and Alibaba Cloud

*An agentic surveillance camera powered by edge AI, computer vision, and Qwen.*

[ VISUAL — Hero banner. AI image prompt: "Wide cinematic banner of a small smart security camera on a pan-tilt mount overlooking a dimly lit shop back entrance at night, with a subtle glowing neural-network overlay tracing a person near the door, teal and amber color palette, futuristic but realistic, no text" ]

## The Problem: Cameras That Record Everything but Understand Nothing

Picture this. At 2:17 a.m., someone appears near the rear entrance of a small shop. The camera records them approaching the door, waiting several minutes, leaving, and coming back.

The footage exists. But unless someone is watching at that exact moment, nothing happens. By the time the owner reviews it the next morning, the event is long over.

That's the core limitation of today's CCTV: **it remembers well, but it doesn't understand.**

Modern systems can detect people, vehicles, or motion — but they depend on rigid settings: zones, labels, confidence thresholds, fixed schedules. A person walking past the shop and someone lingering beside a restricted entrance trigger the *same* alert, even though the situations are completely different.

Users shouldn't need to think like computer-vision engineers. They should be able to just tell the camera:

> "Alert me if someone stays near the rear entrance for more than 20 seconds after closing time."

That one sentence became the foundation of **Erlang AI Vision** — a surveillance platform that:

- understands natural-language rules,
- detects activity locally at the edge,
- escalates only relevant events to Qwen for contextual verification,
- gathers more evidence when it needs to,
- and keeps every decision and camera action auditable.

Instead of simply recording what happened, the camera becomes an active agent that can **understand, investigate, and explain**.

## Introducing Erlang AI Vision

Erlang AI Vision is a full-stack IoT surveillance platform that turns ordinary cameras into configurable AI agents.

Instead of hand-picking detection classes, confidence levels, and schedules, you describe what you want monitored in plain language — by typing a rule directly, or by refining it conversationally with the built-in agent builder:

- *"Alert me if someone stays near the rear entrance after 10 p.m."*
- *"Alert me if my baby cries."* (yes, sound too — the edge runs audio detection alongside vision)

Here's what happens behind the scenes:

1. **Qwen compiles** your instruction into a structured detection rule.
2. **Local models** watch the video and audio streams on the edge device and filter out routine activity — no frames leave the building.
3. **When something matches the rule**, selected evidence goes to Qwen-VL for contextual verification.
4. **You get** not another motion alert, but a **verified event** with a clear reason, supporting evidence, and an audit trail of every action taken.

[ VISUAL — Product demo GIF or storyboard. AI image prompt: "Clean 4-panel UI storyboard of a mobile security app: panel 1 shows a chat box where a user types a monitoring rule, panel 2 shows a live camera view of a doorway, panel 3 shows an AI analyzing a highlighted person with bounding box, panel 4 shows a push notification with a verified alert and explanation, modern flat design, teal accent color" ]

## How It Works: A Four-Layer Architecture

Erlang AI Vision spans from a tiny camera module all the way to the cloud, in four layers:

[ VISUAL — Architecture diagram. AI image prompt: "Clean horizontal system architecture diagram with four connected layers: a small ESP32 camera board, a laptop labeled edge bridge with AI model icons (YOLO, audio, local LLM), a cloud section with server and database icons, and a smartphone showing an alert; arrows flowing left to right, minimal flat tech illustration style, white background, teal and navy palette" ]

**1. Camera (ESP32-S3).**
A XIAO ESP32-S3 module captures JPEG frames — VGA at ~15 FPS over USB, or CIF at ~30 FPS over Wi-Fi (USB has the uplink headroom for the full 640px keyframes the triage model wants) — provisions itself by scanning a pairing QR code, and drives pan/tilt servos.

**2. Edge bridge (laptop).**
The bridge receives frames over LAN or USB and runs the local AI pipeline: YOLO for video detection, YAMNet for audio events, and a local Qwen model (via Ollama) for first-pass triage. It also handles auto-tracking: when enabled, the camera physically follows the subject, aiming at their face (a ~5 ms YuNet pass) when one is visible — and when several people are in view, it frames the whole group instead of fixating on one person. Routine activity dies here — it never leaves the building. *(Measured: a 98.8% bandwidth reduction on a worst-case always-busy scene — see [Evaluation and Results](#evaluation-and-results).)*

**3. Cloud backend (Alibaba Cloud).**
Candidate events reach a FastAPI backend, where Qwen-VL verifies whether the evidence actually matches the user's rule. ApsaraDB stores event data; OSS stores clips and media.

**4. App (Flutter).**
Verified alerts stream to the Flutter web and Android app in real time over SSE, with push notifications via FCM for high-severity events. The app also offers live view, on-demand recording, and in-app playback of event clips (encoded as H.264 specifically so browsers will play them inline instead of forcing a download).

The design principle throughout:

> **Detect locally. Verify intelligently. Alert selectively.**

This split matters for more than cost. Keeping raw footage on the local network is a real privacy boundary — the cloud only ever sees the handful of frames tied to a candidate event, never your continuous video stream.

## Why Qwen Is Essential

Object detection can tell you *a person is present*. It cannot tell you whether that **matters**.

Qwen closes that gap in three places — and each one covers a failure mode the system would otherwise have.

### 1. Natural-Language Agent Builder

Qwen Plus converts a plain-language request into a structured surveillance agent: object classes, schedule, dwell time, confidence threshold, cooldown, and optional region of interest.

Without it, every user would be back to configuring detection zones and thresholds by hand — the exact expertise barrier we set out to remove. (A deterministic keyword compiler serves as fallback, so agent creation never fails even if the cloud is unreachable.)

[ VISUAL — Rule compilation illustration. AI image prompt: "Simple two-sided infographic: on the left a speech bubble with handwritten-style natural language sentence, an arrow through a glowing AI chip icon in the middle, and on the right a neat structured card showing fields like object type, schedule, dwell time and threshold as form rows, flat minimal design, white background" ]

### 2. Contextual Event Verification

YOLO detects *what is present*; Qwen-VL determines *what it means*.

Without this stage, a delivery driver pausing at the door and a person casing the entrance generate identical alerts — the false-positive problem that makes people ignore their camera notifications entirely. Qwen-VL reviews the evidence against the user's actual rule and returns a verdict with an explanation.

> **Edge models detect what is present. Qwen understands what it means.**

### 3. Conversational Surveillance Assistant

Qwen Plus also powers the in-app assistant. Ask *"Show me all events detected at the rear entrance last night"* and it retrieves event history, summarizes activity, and explains why a particular alert fired.

Without it, users would be scrubbing timelines — the same manual review problem CCTV has always had, just with better bookmarks.

**Agent creation, visual verification, conversational investigation** — Qwen isn't a chatbot bolted on top. It is the intelligence layer connecting the entire workflow.

## What Makes It *Agentic*

The verification stage is not a single API call. When evidence is unclear, the Qwen agent can use approved tools to investigate on its own:

- **Request another snapshot** — a person half out of frame? Grab a fresh image.
- **Pan or tilt the camera** — physically adjust the view to see more.
- **Check recent events** — has this happened before tonight?
- **Read camera status** — is the device healthy and pointed where expected?
- **Re-evaluate with the new evidence** — then decide.

[ VISUAL — Agent investigation loop. AI image prompt: "Circular flow diagram with five stages labeled Observe, Reason, Gather Evidence, Verify, Alert, each with a small icon (eye, brain, camera, checkmark shield, bell), arrows forming a loop, one stage highlighted showing a camera physically rotating, modern flat infographic style, teal and navy on white" ]

But none of this happens without control:

- Every tool request is **validated by the FastAPI backend** before execution.
- Commands are relayed to the edge bridge over WebSocket, executed, and written to a **tool audit log** — request and result.
- Camera movement is **clamped to safe mechanical ranges** (pan 15–165°, tilt 60–140°, matching the firmware's hard stops), enforced server-side, so no model output can drive the servos past their limits.

The result is an investigation loop:

> **Observe → reason → gather evidence → verify → alert**

Not just a detection system — a surveillance agent that actively investigates while keeping the user in control.

## Built Across the Edge and Alibaba Cloud

The project spans three repositories, one per tier:

| Tier | Repo | Role |
|------|------|------|
| Cloud + App | `erlang-ai-vision-fullstack` | FastAPI backend + Flutter console: auth, agents, live video, verification |
| Edge bridge | `SentinelEdge_LaptopEdge` | YOLO/YAMNet detection + local Qwen (Ollama) triage |
| Camera | `SentinelEdge_IOT` | ESP32-S3 firmware, QR provisioning, pan/tilt servos |

On the cloud side, everything runs on Alibaba Cloud in the Kuala Lumpur region (`ap-southeast-3`):

- **ECI (Elastic Container Instance)** hosts the FastAPI backend, with a **Caddy sidecar** serving the app and API from a single origin behind a static EIP.
- **ACR** stores the container images; deployment is one script (`backend.ps1 -Deploy`): build → smoke test → push → roll the container group.
- **ApsaraDB RDS PostgreSQL** replaces local SQLite in production, with Alembic migrations and an all-or-nothing, dry-run-first data migration script.
- **OSS** does double duty: one bucket serves the Flutter Web (WASM) build, another stores event clips and media accessed through signed URLs.
- **DashScope** provides Qwen Plus and Qwen-VL.
- **Firebase** handles identity and push; runtime secrets load from a secret manager with least-privilege access — the runtime identity can read app secrets but never database-superuser credentials.

The stack held up in testing: **148 backend tests passing**, Flutter analysis clean, and a **zero-hardware demo mode** so judges can experience the full pipeline — real Qwen-VL verification included — without owning an ESP32.

## Four Engineering Challenges That Ate the Hackathon

Four problems consumed far more time than any feature.

### 1. The cloud can't call your camera

The ESP32 sits on a home LAN behind NAT — the backend can never reach it directly.

So we inverted the relationship: the edge bridge holds a **persistent outbound WebSocket** to the backend, and every command (pan, tilt, snapshot — whether from a user tapping the app or from Qwen calling a tool mid-verification) travels down that same relay, with results flowing back up.

One command path. Fully audited. No port forwarding. No exposed cameras.

[ VISUAL — NAT relay diagram. AI image prompt: "Simple network diagram showing a cloud server on the right unable to reach a camera behind a home router firewall (red blocked arrow), and below it the solution: a laptop inside the home network opening an outbound green arrow to the cloud labeled persistent WebSocket, with commands flowing back through it to the camera, flat minimal style" ]

### 2. Alibaba OSS refuses to render your web app

OSS force-downloads HTML on its public endpoints via an `x-oss-force-download` header — and no bucket setting disables it. Our Flutter web build uploaded perfectly… and then downloaded itself as a file in every browser.

After ruling out an ALB in front of the bucket (there's no OSS backend type, and Host rewrites re-trigger the download), the fix was the **Caddy sidecar**: it reverse-proxies the bucket over the region-internal endpoint, strips the forced-download headers, and — as a bonus — puts the app and API on one origin, eliminating CORS entirely.

### 3. Live video in a browser that can't send auth headers

Browsers can't attach `Authorization` headers to `<img>` requests, so authenticated MJPEG streaming needed short-lived **signed stream URLs** minted per viewing session.

Behind that sits an in-memory frame broker that keeps only the latest frame per device and fans it out to subscribers — no queue backlog, no stale video.

### 4. The tiny model that silently said no to everything

The edge triage stage uses a very small local Qwen model, and small models don't always honor the output format you asked for — Ollama's structured-output enforcement quietly doesn't apply to every model. Ours would answer with `"trigger"` instead of `"triggered"`, bare `key=value` lines, or `triggered (true)`.

Our parser saw none of its expected keys, defaulted every verdict to *false* — and the pipeline "worked" perfectly while escalating **zero events**, ever. No error, no crash, just a surveillance system that had politely stopped surveilling.

The fix was a defensive verdict parser that accepts the shapes the model actually produces. The lesson was broader: **never trust a small model's output shape**, even when the API claims to enforce a schema. Parse defensively, and alarm on "suspiciously quiet" as loudly as on errors.

**The rule compiler never fails.** If Qwen is unreachable, rate-limited, or returns something malformed, a deterministic keyword compiler takes over. Agent creation degrades gracefully instead of erroring — a small thing that made every demo, test run, and offline dev session smoother.

## Hardening the Weakest Link: the Camera Itself

A surveillance product that is itself easy to spy on is worse than no product, so the final stretch went to a security pass on the camera-to-laptop boundary — the part of the system that lives on an untrusted home LAN.

- **The pairing QR no longer carries a cloud credential.** Originally the QR handed the camera the same token the bridge uses to talk to the backend. Now the camera receives only a one-way secret derived from it (HMAC-SHA256), so nothing the camera stores — or leaks — can authenticate against the cloud.
- **A camera must prove itself before it's trusted.** The bridge won't promote a WebSocket connection to "active camera" until it answers a fresh nonce challenge with the correct HMAC — so a random device on the LAN can't impersonate the camera or knock the real one offline.
- **Everything local is bounded and quiet.** The bridge's preview server binds to loopback only, message sizes and frame/byte rates are capped, and firmware health reports no longer include anything credential-shaped.

None of this changes what the demo looks like — which is exactly the point. Security work is the feature you ship so nobody ever notices it.

## Evaluation and Results

Claims about "efficient edge AI" are cheap, so we benchmarked ours. The harness (`scripts/bench_pipeline.py` in the edge repo) drives the **real** pipeline — YOLO detection, per-agent filtering, local Qwen triage, clip recording, routing — with a simulated VGA @ 15 FPS camera; the only thing substituted is the network, replaced by a byte-counting stub.

The models under test are the production edge stack: **YOLO26-nano** for stage-1 detection, and **Qwen3.5 0.8B** (via Ollama, thinking off, 512 px keyframes, kept resident in memory) as the stage-2 triage VLM — with **Qwen3.5 4B** on standby as the offline-mode authority, and DashScope's **Qwen-VL** handling cloud verification beyond the edge. Hardware: an ordinary laptop (AMD Ryzen 7 5800U, CPU-only inference — no GPU anywhere in these numbers).

**Bandwidth — the headline.** Over a 3-minute window on a deliberately worst-case scene (a person and a dog visible almost continuously, so agents fire at their cooldown rate the entire time):

| Direction | Volume | Rate |
|---|---|---|
| Camera → edge (what stream-everything would upload) | 107 MB | 2.14 GB/h |
| Edge → cloud (event JSON + evidence clips) | 1.3 MB | ~26 MB/h |

That is a **98.8% bandwidth reduction (~83× less)** — and it's a floor, not an average: a quiet scene sends nothing at all. Of 2,703 frames fed in, 18 became stage-1 candidates and only 14 were escalated with a ~10-second evidence clip; everything else never left the building.

**Latency.** Stage-1 detection runs at p50 **114 ms** per frame, so the camera reacts to the world in near real time. The local Qwen triage verdict takes p50 **8.7 s** per event on pure CPU (p95 11.1 s), putting the full candidate-detected → event-escalated path at p50 **12.9 s**. The breakdown says this is a hardware floor, not an architecture one — the same triage call runs in ~1–2 s with GPU offload, which is exactly why the roadmap points at Jetson-class edge hardware.

**Efficiency.** Each locally-triaged event costs ~350 tokens on the local model — meaning a *rejected* false positive costs the cloud precisely zero.

**Correctness.** 148 backend tests passing, Flutter analysis clean, and the edge pipeline's tests run against the real models (YOLO, YAMNet, Qwen via Ollama) rather than mocks.

Full methodology, tables, and caveats live in the edge repo's `docs/BENCHMARKS.md`. Not yet measured — and we'd rather say so than hand-wave: cloud verification latency, cost per verified event, and false-positive reduction against a threshold-only baseline (which needs labeled footage).

## Potential Real-World Impact

The pattern generalizes well beyond a shop's rear entrance:

- **Small businesses** get after-hours monitoring that distinguishes a loiterer from a passer-by — without paying for a human monitoring service or drowning in motion alerts.
- **Home care**: "alert me if my baby cries," "tell me if grandma hasn't appeared in the kitchen by 10 a.m." — rules that today require dedicated single-purpose devices.
- **Privacy-sensitive settings** benefit from the edge-first split: continuous footage stays on the local network, and only event-tied evidence ever reaches the cloud.
- **Cost**: cloud vision models are far too expensive to run on every frame. Local triage means Qwen-VL is consulted only for the events that matter. *(Estimated cost per verified event: [MEASURE].)*

The broader point: **natural language is the right configuration interface for the physical world.** The dwell times, confidence thresholds, and schedules still exist — but they've become compiler output, not user burden.

[ VISUAL — Use-case collage. AI image prompt: "Three-panel illustration showing everyday AI camera use cases: a small shop back door at night, a peaceful baby nursery with a crib, and a cozy kitchen where an elderly woman makes tea, each panel with a subtle camera icon and soft detection outline, warm friendly flat illustration style, consistent palette" ]

## Our Team and Build Journey

<!-- TODO: 2–3 sentences per teammate: name, role (firmware / edge pipeline / backend / Flutter), and one thing they owned. -->

We built Erlang AI Vision for the **Qwen Cloud Global Hackathon (Track 5 — EdgeAgent)**.

The build spanned all four layers — firmware, edge pipeline, cloud backend, and app — which meant most weeks involved debugging at least two of them simultaneously: servo ranges one day, WebSocket reconnection semantics the next, OSS response headers after that.

<!-- TODO: 1 short paragraph of honest journey color: what nearly didn't work, the moment the first end-to-end alert fired, etc. -->

## What We Learned

- **Put the model behind a contract, not in charge.** Qwen proposes tool calls; the backend validates every one, clamps physical actions to safe ranges, and logs everything. Agentic behavior and user control are not in tension — the audit layer is what makes the autonomy acceptable.
- **Design for the model being unavailable.** Fallback compilation, optional verification stages, and an edge tier that keeps detecting during cloud outages turned reliability from a risk into a feature.
- **The edge/cloud split is a product decision, not just an infrastructure one.** Where inference runs determines the privacy story, the cost story, and the latency story all at once.
- **Demo modes are worth building early.** The zero-hardware simulation mode, originally for judges, became our main development tool.

## What Comes Next

- **Measure the rest**: edge-side bandwidth and latency are benchmarked above; still open are cloud verification latency, cost per verified event, and false-positive reduction against a threshold-only baseline.
- **Harden for weak networks**: event queueing and replay across disconnects, and full local operation during cloud outages.
- **Move the edge tier off the laptop** onto dedicated single-board hardware (Jetson/RK3588-class) — the laptop was the right prototype, not the destination.
- **Richer investigations**: multi-camera correlation, longer temporal context, and human-confirmation gates for higher-risk physical actions.

## Conclusion

CCTV has spent decades getting better at remembering — and almost no better at understanding.

Erlang AI Vision is our answer: describe what matters in a sentence, let edge models watch cheaply and privately, and let Qwen verify, investigate, and explain the moments that matter.

> **Detect locally. Verify intelligently. Alert selectively.**

- 🔗 **Live demo**: [TODO: URL]
- 🎬 **Demo video**: [TODO: URL]
- 💻 **Code**: [erlang-ai-vision-fullstack](TODO) · [SentinelEdge_LaptopEdge](TODO) · [SentinelEdge_IOT](TODO)

*Built for the Qwen Cloud Global Hackathon, Track 5 — EdgeAgent, on Alibaba Cloud.*
