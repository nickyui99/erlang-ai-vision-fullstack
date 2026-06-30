# Erlang AI Vision Rebrand Plan

## Summary

Rebrand the product-facing Fullstack UI from SentinelEdge to **Erlang AI Vision** while keeping backend APIs, repo names, package identifiers, database names, Firebase project names, and service identifiers stable for now.

The rebrand uses the approved red/orange camera-eye reference direction and updates Flutter web/mobile branding, app icons, theme colors, selected UI dependencies, and user-facing copy.

## Brand Direction

| Token | Value | Use |
|---|---|---|
| Product name | Erlang AI Vision | User-facing app name and marketing copy |
| Primary red | `#F03A24` | Primary actions, selected nav, brand mark |
| Primary dark | `#C91F14` | Pressed states, dark accents |
| Accent orange | `#FF6A2A` | Highlights, circuit detail, focus accents |
| Ink | `#111820` | Primary text |
| Dark surface | `#0D1117` | Dark mode shell/cards |
| Light background | `#F7F8FA` | Main light scaffold background |
| Card/surface | `#FFFFFF` | Panels/cards |
| Border | `#E4E7EC` | Hairline borders |

Semantic status colors remain separate from brand colors: green for online/armed, amber for warning/degraded, red for offline/error, and blue/slate for info/sync.

## Asset Inventory

Generated assets live in `frontend/sentineledge_app/assets/brand/`:

- `erlang-ai-vision-logo.png`
- `erlang-ai-vision-logo-dark.png`
- `erlang-ai-vision-logo-light.png`
- `erlang-ai-vision-icon.png`
- `erlang-ai-vision-icon-dark.png`
- `erlang-ai-vision-icon-red.png`

Platform icon outputs:

- Web favicon: `frontend/sentineledge_app/web/favicon.png`
- Web/PWA icons: `frontend/sentineledge_app/web/icons/`
- Android launcher icons: `frontend/sentineledge_app/android/app/src/main/res/mipmap-*/ic_launcher.png`
- iOS app icons: `frontend/sentineledge_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/`

Old SentinelEdge logo image assets have been removed after migrating active Flutter references to Erlang AI Vision assets.

## UI Library Decision

Material 3 remains the base because the app already uses `ThemeData`, `ColorScheme`, and local design tokens. The ready UI packages are added selectively:

- `shadcn_ui` for modern SaaS components where useful.
- `lucide_icons_flutter` for thin-line dashboard icons.
- `flutter_animate` for small state transitions.

`flutter_adaptive_scaffold` is deferred because it is currently discontinued; the existing responsive shell remains in place until a maintained adaptive layout package is chosen.

## Implementation Checklist

- Replace product-facing names with Erlang AI Vision in Flutter app title, web metadata, Android label, iOS display name, auth screen, dashboard shell, settings/about copy, and tests.
- Replace logo image references with Erlang AI Vision assets.
- Update theme colors in `AppColors` to the red/orange/black/white palette.
- Keep backend API paths, package names, Firebase project IDs, repo names, and service identifiers unchanged.
- Keep generated secrets and local DB files out of Git.

## Acceptance Criteria

- App launches with Erlang AI Vision as the visible product name.
- New logo appears in auth and dashboard shell.
- Web favicon/PWA icons use the Erlang AI Vision mark.
- Android/iOS launcher icons use the Erlang AI Vision mark.
- Light and dark themes use the new palette while preserving status colors.
- `flutter analyze` and `flutter test` pass.
- Remaining `SentinelEdge` references are limited to technical identifiers, repo/service names, API client names, package names, Firebase project names, or intentionally deferred docs.

