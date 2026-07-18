# Devpost Copy — Erlang AI Vision

## Tagline

Qwen-powered agent cameras that turn plain-language safety rules into private, edge-first monitoring and verified cloud alerts.

## What it does

Erlang AI Vision is an edge-first AI camera platform for homes and small businesses. A user writes a rule such as “alert me if someone lingers at the door after 9pm.” The platform converts it into an armed camera agent, watches the stream at the edge, and sends only meaningful candidate events to Qwen Cloud for final verification.

The Flutter console provides live camera views, event playback, realtime alerts, agent configuration, and an in-app Erlang AI Agent. That agent uses the platform’s MCP server to inspect cameras, query events, take snapshots, and safely control pan/tilt functions with audit logging and guardrails.

## Why Qwen Cloud is essential

Qwen is the reasoning layer across the whole system:

- Qwen text models translate natural-language monitoring rules into detector configuration and power the agentic assistant.
- Qwen vision verifies high-value edge events using an image, relevant recent context, and audited tools such as snapshot retrieval and bounded camera movement.
- Smaller Qwen models run locally on the edge for low-latency triage and degraded-network operation.

This layered approach preserves privacy, cuts bandwidth, and reserves cloud inference for events worth verifying.

## Architecture

1. ESP32-S3 camera captures frames and supports guarded pan/tilt control.
2. Laptop Edge Bridge performs local detection and Qwen/Ollama triage.
3. FastAPI on Alibaba Cloud ECI manages authentication, agents, events, realtime updates, MCP tools, and Qwen Cloud verification.
4. Flutter Web is served through the same HTTPS origin; media is stored in Alibaba OSS and metadata in ApsaraDB RDS PostgreSQL.

## Demo and judge flow

The deployed application includes a zero-hardware judge mode: pre-extracted camera frames are streamed server-side into demo cameras and use the same Qwen verification path as the normal flow. A judge can sign in, open a camera, create or inspect an agent, view the resulting event, and inspect the audit trail without physical hardware.

## Security and deployment

The production deployment uses HTTPS, restricted CORS, secure session cookies, CSRF origin checks, production-only rate limits, request-size limits, private RDS networking, signed OSS URLs, and managed secrets. FastAPI documentation endpoints are disabled in production. Qwen credentials are mandatory in production, and local/mock Qwen fallbacks are rejected there.

## Links to add in Devpost

- Live application: https://erlang-ai.duckdns.org
- Source: https://github.com/nickyui99/erlang-ai-vision-fullstack
- Edge source: https://github.com/KennethChua1998/SentinelEdge_LaptopEdge
- Firmware source: https://github.com/KennethChua1998/SentinelEdge_IOT
- Architecture/deployment proof: docs/deployment/alibaba_cloud_architecture.md in the fullstack repository
- Demo video: add after upload