# Edge Link Security Hardening Design

**Date:** 2026-07-15
**Status:** Approved approach; written specification pending user review

## Objective

Harden the pre-deployment camera-to-laptop boundary so that an untrusted LAN client cannot impersonate a camera, displace the active camera connection, steal the cloud edge token from telemetry, or exhaust the laptop bridge with unbounded input.

This is the first security-hardening phase. Cloud HTTPS, OSS upload policy, MCP confirmation, dependency upgrades, and production deployment controls are separate follow-up phases.

## Security invariants

1. The backend cloud `edge_token` is held only by the backend, authenticated Flutter client during the one-time registration response, and laptop edge process. It is never encoded in the camera QR, stored by firmware, transmitted in device health, or accepted from device telemetry.
2. The camera receives a one-way `device_link_secret` derived from the edge token. Possessing this derived secret must not reveal or authenticate as the cloud edge token.
3. A WebSocket connection is not promoted to the active camera until it completes a fresh nonce/HMAC challenge. An unauthenticated connection cannot disconnect or replace the authenticated camera.
4. Local preview is loopback-only, does not emit wildcard CORS, and never returns credential-shaped health fields.
5. WebSocket messages, per-frame payloads, serial input, HTTP request headers, preview clients, frame rate, and byte rate are bounded.
6. QR fields and firmware serialization lengths are checked before persistence or transmission. A truncated `snprintf` result is never used as an out-of-bounds send length.
7. Edge secrets are passed to child processes through their environment, never command-line arguments or GUI logs, and are not persisted in the console JSON file.

## Credential derivation and pairing

The backend adds:

```text
DEVICE_LINK_DERIVATION_LABEL = b"sentineledge-device-link-v1"
device_link_secret = base64url_no_padding(
    HMAC-SHA256(key=edge_token UTF-8 bytes, message=DEVICE_LINK_DERIVATION_LABEL)
)
```

The value is 43 URL-safe characters. Device registration returns both `edge_token` and `device_link_secret`. The backend stores neither raw value beyond the existing hashed edge-token storage.

The Flutter pairing QR uses schema version 2:

```json
{
  "v": 2,
  "s": "wifi-ssid",
  "p": "wifi-password",
  "h": "laptop-host",
  "o": 8765,
  "path": "/",
  "k": "43-character-device-link-secret"
}
```

The QR must not contain `t`, `edge_token`, or any cloud API credential. The UI labels the returned cloud token as a **Laptop bridge token**, tells the user it must never be scanned into the camera, and keeps it out of QR debug text.

The laptop derives the same `device_link_secret` from its configured edge token. For local-only development without a backend token, `SENTINELEDGE_DEVICE_LINK_SECRET` may supply the derived 43-character value directly. There is no command-line flag for either secret.

The laptop simulator behaves like firmware: it receives only `SENTINELEDGE_DEVICE_LINK_SECRET`, completes the same challenge, and never receives the cloud edge token. The edge console derives the link secret once and supplies separate child environments: the bridge receives the cloud token, while the simulator receives only the derived link secret. Legacy receiver utilities that open a Wi-Fi `DeviceHub` require the link-secret environment variable before listening.

Existing version-1 camera configuration is intentionally rejected. Because the product has not deployed, upgraded cameras must be re-paired rather than retaining an insecure compatibility mode.

## Camera authentication protocol

Protocol strings are fixed and versioned:

```text
challenge type: auth.challenge
response type:  auth.response
success type:   auth.ok
MAC label:      sentineledge-link-auth-v1:
```

1. The bridge accepts a WebSocket transport but does not assign it to `DeviceHub.client`.
2. The bridge creates 32 random bytes, encodes them with unpadded base64url, and sends `{"type":"auth.challenge","nonce":"..."}`.
3. Within five seconds, firmware responds with the same nonce and:

   ```text
   mac = base64url_no_padding(
       HMAC-SHA256(
           key=device_link_secret UTF-8 bytes,
           message=UTF-8("sentineledge-link-auth-v1:" + nonce)
       )
   )
   ```

4. The bridge validates exact JSON fields, nonce equality, URL-safe lengths, and the MAC using constant-time comparison.
5. Only after success does the bridge send `{"type":"auth.ok"}`, close the previous authenticated socket, and promote the new socket.
6. Firmware sets its streaming-ready flag only after `auth.ok`. Before that, text messages are accepted only for the authentication protocol and binary streaming remains disabled.
7. Authentication failure, malformed input, or timeout closes only the candidate connection.

The fresh server nonce prevents replay. This phase authenticates the connection but does not encrypt LAN video; WSS with certificate pinning remains the next transport phase.

## Firmware provisioning and bounds

`ProvisionConfig.edgeToken` is replaced by `ProvisionConfig.deviceLinkSecret`. NVS key `edge_token` is erased during successful version-2 provisioning and is never read. A usable Wi-Fi configuration requires SSID, host, and valid link secret.

Accepted field constraints:

| Field | Constraint |
|---|---|
| `v` | exactly integer `2` |
| `s` | 1–32 bytes |
| `p` | 0–63 bytes |
| `h` | 1–253 bytes |
| `path` | 1–128 bytes and begins with `/` |
| `o` | integer 1–65535 |
| `k` | exactly 43 ASCII base64url characters |

Serial logs report only schema version, host, and port. They never print the QR payload, SSID, password, or secret.

Health JSON contains only operational telemetry. Serialization handles `snprintf` errors and sends at most `sizeof(buffer) - 1` bytes.

## Bridge and preview limits

The Python WebSocket server uses:

```text
max_size = 131072 bytes
max_queue = 4 messages
compression = None
authentication timeout = 5 seconds
maximum video frames = 30 per second
maximum aggregate input = 4 MiB per second, with a one-second window
```

Payload limits, excluding the five-byte protocol header:

| Frame | Maximum |
|---|---:|
| JPEG/video or snapshot | 131,067 bytes |
| Audio | 16,384 bytes |
| Health JSON | 4,096 bytes |

Oversized, over-rate, malformed, or unknown frames close the candidate/current device connection without entering the pipeline.

Serial input is capped at 262,144 buffered bytes. Exceeding it clears the partial record, increments an integrity counter, and resumes at the next complete record.

Preview requirements:

- `stream_host` must resolve as loopback (`127.0.0.1`, `::1`, or `localhost`); any other value fails startup.
- No `Access-Control-Allow-Origin` header is emitted.
- Health output is recursively redacted for keys containing `token`, `secret`, `password`, `authorization`, or `credential` as defense in depth.
- At most four preview clients may be active.
- Request line is at most 2,048 bytes; each header is at most 8,192 bytes; at most 64 headers; the complete header read has a five-second deadline.

## Edge console secret handling

The console may accept the cloud edge token in its masked input for the current process only. It must:

- ignore and remove legacy `edge_token` and `remember_token` values when saving configuration;
- omit both values from `.edge_console.local.json`;
- omit the token from the child argument list and displayed command;
- pass `SENTINELEDGE_EDGE_TOKEN` only to the bridge through a copied child environment;
- derive `SENTINELEDGE_DEVICE_LINK_SECRET` and pass only that value to the simulator child;
- overwrite the in-memory GUI value when the bridge stops or the console closes.

The implementation will not automatically delete the user's existing ignored file or rotate credentials. The handoff must instruct the user to remove the old file and rotate any token previously stored there.

## Error handling

- Missing laptop edge token/link secret: the Wi-Fi device listener does not start; USB-only mode remains available because it has a physical trust boundary.
- Camera with legacy firmware: receives an authentication challenge but cannot authenticate and is disconnected without affecting a current authenticated camera.
- Invalid pairing QR: configuration is not partially written; existing valid NVS configuration remains unchanged.
- Backend registration response missing `device_link_secret`: Flutter treats registration as failed instead of creating a legacy QR.
- Preview configured for a non-loopback host: bridge exits with a clear configuration error before opening the socket.

## Tests and verification

All behavior changes use red-green TDD where the platform supports unit tests.

Backend tests cover deterministic derivation, output format, registration response, and absence of raw secret persistence.

Flutter tests cover parsing `device_link_secret`, version-2 QR contents, absence of `edge_token`/`t`, and revised labeling.

Laptop-edge tests cover successful authentication, wrong secret, replayed response, timeout, unauthenticated displacement prevention, environment-only secret delivery, loopback enforcement, health redaction, CORS removal, input limits, rate limits, and serial cap recovery.

Firmware tests isolate QR-field validation and safe send-length calculation into deterministic helpers suitable for PlatformIO native tests. ESP32 builds verify HMAC integration and WebSocket state transitions compile for `xiao_s3` and `usb_stream`.

Final verification includes the targeted backend, Flutter, laptop-edge, and PlatformIO suites plus repository secret-pattern scans confirming the QR and health paths no longer contain the cloud token.

## Follow-up phases

1. WSS server authentication with certificate/fingerprint pinning for LAN confidentiality.
2. Production HTTPS/HSTS and remote cleartext rejection.
3. Server-enforced OSS upload constraints, object ownership, and quotas.
4. Backend request limits, strong production secret validation, and session revocation.
5. MCP confirmation/data-minimization controls and retention deletion.
6. Dependency, container, Android signing, and deployment supply-chain hardening.
