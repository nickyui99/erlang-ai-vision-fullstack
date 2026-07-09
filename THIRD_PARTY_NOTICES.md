# Third-Party Notices

This repository (`Erlang AI Vision` backend + Flutter console) is released under the
[MIT License](LICENSE). That license covers the code in **this** repository. The
components below are used by or alongside this project under their own licenses.

## Backend dependencies (Python)

All permissively licensed:

| Package | License |
|---|---|
| FastAPI | MIT |
| SQLAlchemy | MIT |
| Alembic | MIT |
| aiosqlite | MIT |
| pydantic-settings | MIT |
| Uvicorn | BSD-3-Clause |
| httpx | BSD-3-Clause |
| asyncpg | Apache-2.0 |
| firebase-admin | Apache-2.0 |
| alibabacloud-* SDKs (KMS, Tea OpenAPI) | Apache-2.0 |

## Frontend dependencies (Flutter / Dart)

All permissively licensed:

| Package | License |
|---|---|
| Flutter SDK, firebase_core/auth/messaging, google_sign_in, http, go_router, shared_preferences, qr_flutter | BSD-3-Clause |
| google_fonts | Apache-2.0 |
| shadcn_ui, flutter_animate, cupertino_icons | MIT |
| lucide_icons_flutter | ISC |

## External services (not bundled; you supply your own credentials)

- **Qwen Cloud (Alibaba DashScope, OpenAI-compatible API)** — used for natural-language
  rule compilation and event verification. Governed by Alibaba Cloud / DashScope terms
  of service; requires your own API key. No Qwen model weights are distributed here.
- **Firebase (Google)** — authentication and Cloud Messaging. Governed by Google/Firebase
  terms; requires your own project credentials.
- **Alibaba Cloud** — OSS, RDS, ECI, KMS for deployment. Governed by Alibaba Cloud terms.

## Sibling repositories (separate licenses)

The physical camera firmware and the local AI edge runtime live in separate repositories
and are **not** part of this MIT-licensed codebase. Notably:

- **`SentinelEdge_LaptopEdge`** bundles/uses **Ultralytics YOLO**, which is licensed under
  **AGPL-3.0** (a copyleft license with stricter terms than MIT), along with **YAMNet**
  (Apache-2.0) and **Ollama**. Anyone distributing or deploying that edge runtime must
  comply with those licenses — in particular the AGPL-3.0 obligations for YOLO.
- **`SentinelEdge_IOT`** — ESP32-S3 firmware; see that repository for its license.

The MIT license of this repository does not extend to those projects or to the
third-party models they use.
