# Erlang AI Vision — Judge Guide

This guide is the shortest path to evaluating the submitted system without needing to assemble hardware.

## 1. Evaluate the live, zero-hardware route

1. Open [erlang-vision.duckdns.org](https://erlang-vision.duckdns.org).
2. Sign in with the judge account supplied in the private Devpost testing instructions.
3. Open a pre-seeded camera, event, or agent. The workspace contains simulated camera feeds, armed agents, verified events, clips, and alerts.
4. Try a plain-language rule such as: `Alert me if a person lingers at the door after 9 p.m.` Then inspect the generated detector configuration.
5. Open **Erlang AI Agent** and ask it to list cameras, inspect events, or take a snapshot. Its actions are made through the platform's MCP server and appear in the audit trail.

**Expected result:** the browser receives live frames and events over HTTPS. A qualifying rule creates an event with a Qwen verification result and an in-app alert. If a live-Qwen dependency is unavailable, the UI reports the degraded state instead of claiming a mock verification.

## 2. Verify the Alibaba Cloud deployment

The backend is deployed in Alibaba Cloud Kuala Lumpur (`ap-southeast-3`) using ECI, ACR, RDS PostgreSQL, and OSS.

- **Direct deployment proof:** [`scripts/deployment/backend.ps1`](scripts/deployment/backend.ps1). With `-Deploy`, it builds the backend image, pushes it to Alibaba Cloud ACR, and provisions or updates the ECI FastAPI + Caddy container group.
- **Architecture:** [`docs/deployment/alibaba_cloud_architecture.md`](docs/deployment/alibaba_cloud_architecture.md).
- **Production URL:** [erlang-vision.duckdns.org](https://erlang-vision.duckdns.org).

## 3. Understand the three repositories

| Repository | Responsibility | What to inspect |
|---|---|---|
| [Fullstack](https://github.com/nickyui99/erlang-ai-vision-fullstack) | FastAPI backend, Flutter app, Qwen Cloud verification, MCP tools, persistence, deployment | This README, deployment script, `backend/tests/`, and the live application |
| [LaptopEdge](https://github.com/KennethChua1998/ErlangAIVision_LaptopEdge) | Edge bridge, YOLO/YAMNet detection, Ollama Qwen triage, offline queue, camera-command relay | Its README and benchmark report |
| [IOT](https://github.com/KennethChua1998/ErlangAIVision_IOT) | ESP32-S3 camera firmware, QR provisioning, pan/tilt servo control | Its README and firmware source |

The full path is: **ESP32-S3 camera → LaptopEdge local filtering → FastAPI/Qwen Cloud verification → audited decision and alert → optional guarded camera action**.

## 4. Optional local Qwen smoke test

To exercise the configured Qwen client locally, after configuring `.env` with your own API key:

```powershell
$env:PYTHONPATH = 'backend'
python scripts/verify_smoke.py
```

This sends one representative event to the configured client and prints the raw reply and normalized verdict. It does not deploy infrastructure or change production data.

## Demo boundaries

The judge route uses simulated camera frames to avoid requiring ESP32 hardware. It still exercises the deployed backend, real Qwen verification, event persistence, clips, alerts, and audited MCP actions. The physical hardware route is available through the companion repositories and the ESP32-S3 pan–tilt prototype shown in the main README.
