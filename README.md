<div align="center">

![Erlang AI Vision — AI-powered security monitoring: real-time detection, smart alerts, camera automation](docs/assets/banner.png)

### Qwen-powered agent cameras you configure in plain language.

*Describe what to watch for in plain English. The AI agent watches, triages, and verifies.*

![License](https://img.shields.io/badge/license-MIT-green)
![Backend](https://img.shields.io/badge/backend-FastAPI-009688)
![Frontend](https://img.shields.io/badge/frontend-Flutter-02569B)
![Edge](https://img.shields.io/badge/edge-ESP32--S3-E7352C)
![AI](https://img.shields.io/badge/AI-Qwen--VL%20%2B%20YOLO-purple)

[**Quickstart**](#-quickstart) · [**Architecture**](#️-architecture) · [**Docs**](#-documentation)

</div>

## 🏆 Qwen Cloud Global Hackathon

Submission for the **Qwen Cloud Global Hackathon — Track 5: EdgeAgent**.

| | |
|---|---|
| **Live application** | [erlang-vision.duckdns.org](https://erlang-vision.duckdns.org) |
| **Demo video** | *coming before submission — will be linked here and on Devpost* |
| **Repositories** | [erlang-ai-vision-fullstack](https://github.com/nickyui99/erlang-ai-vision-fullstack) (cloud + app, this repo) · [SentinelEdge_LaptopEdge](https://github.com/KennethChua1998/SentinelEdge_LaptopEdge) (edge bridge) · [SentinelEdge_IOT](https://github.com/KennethChua1998/SentinelEdge_IOT) (ESP32-S3 firmware) |
| **Deployment** | Alibaba Cloud `ap-southeast-3` (Kuala Lumpur): ECI container (FastAPI + Caddy), OSS (web app + media), RDS PostgreSQL, ACR — [architecture and deployment proof](docs/deployment/alibaba_cloud_architecture.md) |
| **Team** | Nicholas Ooi ([@nickyui99](https://github.com/nickyui99)) · Kenneth Chua ([@KennethChua1998](https://github.com/KennethChua1998)) · Fang Wei Lim · Ng Wei Kiat|

### Qwen models used

| Model | Where it runs | What it does |
|---|---|---|
| `qwen3.7-plus` *(image verification)* | Qwen Cloud (DashScope) | Stage-3 event verification (vision + tool calling) — per-event image work runs on the plus tier to keep costs down (falls back to `qwen3.7-plus-2026-05-26`) |
| `qwen3.7-max` *(chat + text)* | Qwen Cloud (DashScope) | The agentic in-app assistant (Erlang AI Agent), NL-rule compiler, and conversational agent builder (falls back through `qwen3.7-max-2026-05-20` → `qwen3.7-max-preview` → `qwen3.7-max-2026-05-17` → `qwen3.7-max-2026-06-08`) |
| `qwen3.5:0.8b` | **On the edge laptop** via Ollama | Stage-2 triage: judges every candidate keyframe against the user's rule, locally (also the final vision fallback when every cloud model is exhausted) |
| `qwen3.5:4b` | **On the edge laptop** via Ollama | Degraded-mode authority: an agentic tool-calling loop (pan, re-snapshot, re-assess) when the cloud is unreachable |

### Why Qwen is essential

The whole architecture is built around the Qwen family spanning **from a 0.8B
open-weight VLM on a CPU laptop to frontier cloud models** behind one prompt style:

1. **Plain language is the product** — user rules become detector configs through
   Qwen text models; there is no form-based rule editor.
2. **The edge filter needs a local VLM** — `qwen3.5:0.8b` triages every candidate
   frame on the laptop, which is what lets the system drop ~99% of frames before
   any cloud call (bandwidth, cost, and privacy win).
3. **Verification needs vision + tools** — `qwen3.7-plus` doesn't just look at a
   keyframe; it can pan the camera, take a fresh snapshot, and check recent
   events through audited tool calls before ruling.
4. **Offline resilience needs the same brain smaller** — when the cloud is cut,
   `qwen3.5:4b` runs the *same kind* of agentic verification loop locally.

### Built during the hackathon period (after May 26, 2026)

All three repositories were built from scratch during the hackathon window
(first commit June 11, 2026): the FastAPI backend and Flutter console, the
laptop edge pipeline (YOLO/YAMNet + Ollama Qwen triage, offline queue, degraded
mode), the ESP32-S3 firmware with QR provisioning and pan/tilt, the Alibaba
Cloud deployment, and — in the final week — the MCP tool server with the
agentic in-app assistant, on-demand recording, instant agent arm/disarm, and
browser-playable (H.264) event clips. See `HACKATHON_SUBMISSION_CHECKLIST.md`
and the git history for the full trail.

### 🧑‍⚖️ Judge testing instructions

1. **Sign in** at the live application URL with the judge credentials provided
   on Devpost (the account is pre-verified — no email confirmation needed).
2. The dashboard is **pre-seeded**: cameras for each use case, armed agents, and
   sample events, so there is something to explore immediately.
3. **Zero-hardware demo**: judge cameras are simulated server-side — the backend
   streams pre-extracted frames into the live view and runs *real* Qwen-Plus
   detection on them, so the full detect → verify → alert flow works with no
   physical device.
4. Things to try:
   - Create an agent in plain English (e.g. *"alert me if a person lingers at
     the door after 9pm"*) and inspect the compiled detector config.
   - Open the **Erlang AI Agent** chat and ask *"which cameras do I have and
     are any agents armed?"* — it answers from live data via MCP tools, and can
     arm agents or take snapshots for you.
   - Open an event and play its clip; check the audited tool calls on verified
     events.
5. To run everything locally instead (including the physical-device path), see
   the [Quickstart](#-quickstart) below.

**Expected result:** the dashboard loads over HTTPS, a demo camera shows live
frames, and a qualifying rule produces an event with a Qwen verification result
and an in-app alert. If a live-Qwen dependency is unavailable, the UI reports
the degraded state rather than presenting a mock result as live verification.

## 🎬 See it in action


![Erlang AI Vision architecture](docs/assets/erlang-ai-vision-architecture-flow.png)

> No hardware? The backend ships a **zero-hardware demo mode** that plays video
> into a virtual camera and runs real Qwen-Plus detection on it.

## What is Erlang AI Vision?

Erlang AI Vision is a full-stack AI camera platform. Define detection rules in
plain language ("alert me if a person is at the front door after 10pm"), and the
system compiles them into edge detector configs, runs local AI on the camera feed,
and escalates qualifying events to a cloud vision model for verification.

It spans three tiers:

| Tier | Repo | Role |
|------|------|------|
| **Cloud/App** | this repo | FastAPI backend + Flutter console: auth, agents, live video, verification |
| **Edge bridge** | [`SentinelEdge_LaptopEdge`](https://github.com/KennethChua1998/SentinelEdge_LaptopEdge) | Local YOLO/YAMNet detection + Ollama Qwen triage |
| **Camera** | [`SentinelEdge_IOT`](https://github.com/KennethChua1998/SentinelEdge_IOT) | ESP32-S3 firmware, QR provisioning, pan/tilt |

## ✨ Features

- 🗣️ **Natural-language agents** — describe a rule; Qwen Cloud compiles it to a detector config (keyword fallback, never fails).
- 💬 **Conversational agent builder** — draft and refine rules through chat, preview the compiled detector.
- 🤖 **Agentic AI assistant over MCP** — the in-app Erlang AI Agent connects to the platform's own MCP tool server and can inspect cameras, take snapshots, pan/tilt, query events, fetch clips, and create/arm agents for you ([details](#-mcp-tool-server)).
- 🎥 **Live video fan-out** — edge streams JPEG frames; clients view signed MJPEG/frame URLs.
- 🧠 **Two-stage AI** — local YOLO/Qwen triage on the edge, cloud Qwen-Plus verification for high-value events.
- 🔍 **Audited verification tools** — the verifier can pan the camera, grab a snapshot, and read recent events — all logged.
- 🕹️ **Remote control** — pan / tilt / snapshot relayed over WebSocket.
- 🔔 **Realtime + push** — SSE for live updates, FCM for high-severity alerts.
- 🧪 **Zero-hardware demo mode** — simulate cameras from video files with real cloud detection.

## 🏗️ Architecture

```mermaid
flowchart TD
    App[Flutter Console] <--> BE[FastAPI Backend]
    BE <--> Edge[Laptop Edge Bridge]
    Edge <--> Cam[ESP32-S3 Camera]
    BE --> Qwen[Qwen Cloud Verification]
    Edge --> Local[YOLO / YAMNet / Ollama]
```

> The backend never talks directly to a LAN camera. The edge bridge keeps an
> outbound connection open to the backend and relays commands to the camera.

<details>
<summary>Detailed data flow</summary>

```text
Erlang AI Vision Flutter console
  -> FastAPI backend (this repo)
      - auth/session/device/agent APIs
      - live MJPEG stream broker
      - edge command relay over WebSocket
      - event/media/alert persistence
      - Qwen Cloud verification + MCP-style tools
  <- Laptop edge bridge (SentinelEdge_LaptopEdge)
      - receives ESP32 frames/health/commands
      - runs YOLO/YAMNet/Ollama local pipeline
      - posts candidate events and media metadata
  <- ESP32 camera firmware (SentinelEdge_IOT)
      - captures JPEG frames
      - scans pairing QR for Wi-Fi + bridge address
      - drives pan/tilt servos
```

</details>

## 🔌 MCP tool server

The platform's tools are exposed as a standard **Model Context Protocol** server
(streamable HTTP) at `POST {API_PREFIX}/mcp/` — by default
`http://localhost:8000/api/v1/mcp/`. The in-app **Erlang AI Agent** chat connects
to it as an ordinary MCP client each turn, so anything it can do, any external
MCP client (Claude, IDEs, agent frameworks) can do too with a valid token.

**Tools** (all scoped to the authenticated user's own data):

| Group | Tools |
|---|---|
| Cameras | `list_devices`, `get_device_status`, `get_live_snapshot`, `pan_camera`, `tilt_camera` |
| Events & media | `query_events`, `get_event_clip`, `list_recordings` |
| Agents | `list_agents`, `create_agent`, `assign_agent`, `unassign_agent` |

**Auth**: requests carry `Authorization: Bearer <token>` where the token is a
short-lived signed `mcp_access` token minted by the backend (the chat service
mints one per turn; a user-facing token endpoint is on the roadmap for external
clients). Requests without a valid token are rejected before reaching the
protocol layer.

**Guardrails**: every call is permission-checked against a chat-scope autonomy
table (emergency escalation is denied), camera movement is clamped to
servo-safe ranges and rate-limited, every tool call is audited to `tool_audit`,
and chat turns are capped per account per day (`CHAT_DAILY_MESSAGE_LIMIT`,
default 50/day) since one agentic turn can spend several Qwen calls. If the
MCP server is unreachable, the chat degrades gracefully to text-only answers.

## 🚀 Quickstart

```powershell
# 1. Backend deps + env
pip install -r backend\requirements.txt
#    expected: ends with "Successfully installed ..." (no red ERROR lines)
Copy-Item .env.example .env

# 2. Initialize or upgrade the local SQLite schema
python -m alembic -c backend\alembic.ini upgrade head
#    expected: "Running upgrade ..." lines ending at the head revision, exit code 0

# 3. Run backend + Flutter web together
.\scripts\start-dev.ps1
#    expected: backend logs "Uvicorn running on http://0.0.0.0:8000",
#    Flutter logs "lib\main.dart is being served at http://localhost:8080"
```

API docs: `http://localhost:8000/docs` · App: `http://localhost:8080`
**Expected result:** the app loads at `localhost:8080` and `http://localhost:8000/healthz` returns `{"data":{"status":"ok"}}`.

**Try it with no hardware:**

```powershell
$env:PYTHONPATH="backend"
python scripts\create_judge_account.py     # seed demo login + cameras + agents
#    expected: ends with "=== judge demo account ready ===" and the login credentials
```

Set `DEMO_SIMULATION_ENABLED=true` and a Qwen vision model in `.env`, then open a
demo camera's live view. The backend sends its first frame to Qwen after four
seconds and sends at most one more frame per minute.

Full setup → [Backend setup](docs/backend/backend_setup.md) · [Frontend setup](docs/frontend/frontend_setup.md)

## 📚 Documentation

- [Backend architecture](docs/backend/architecture.md)
- [API endpoints](docs/backend/api_endpoints.md)
- [Edge integration](docs/backend/edge_integration.md)
- [Media storage](docs/backend/media_storage.md)
- [Deployment (Alibaba Cloud)](docs/deployment/alibaba_cloud_architecture.md)

**Related repos:** `SentinelEdge_LaptopEdge` (edge pipeline) · `SentinelEdge_IOT` (ESP32 firmware)

---
<div align="center">

Licensed under the [MIT License](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md) · Built for the Erlang AI Vision hackathon.

</div>

<!--
  ASSETS: banner.png is wired in (save it under docs/assets/). Still optional:
  - demo.gif     10-15s     chat a rule -> live view -> event fires -> alert
-->
