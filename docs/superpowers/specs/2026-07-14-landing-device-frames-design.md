# Landing Laptop and Mobile Frame Design

**Date:** 2026-07-14  
**Status:** Approved revised direction

## Goal

Keep the original live-console hero, remove the static metric row, and present the product across desktop and mobile with an enlarged laptop plus an overlapping phone.

## Final composition

- Remove Online cameras, Armed agents, and Qwen verdicts from the hero.
- Preserve the live camera, Protection agent, audit activity, and camera controls inside the laptop.
- Use `assets/landing/laptop-frame.png` as the transparent laptop overlay.
- Use `assets/landing/mobile-agent-frame.png` for the supplied Erlang AI Agent mobile screen.
- Position the phone in front of the laptop's left edge and bottom-align the devices.
- Let the laptop extend slightly wider than the original preview so its screen remains prominent.
- Keep navigation and hero actions unchanged.

## Asset requirements

Both device cutouts are built-in imagegen outputs produced on flat chroma key and converted to alpha. The mobile asset preserves the user-supplied agent screen inside a graphite phone shell. No device asset may include an exterior background or watermark.

## Responsive behavior

Scale both devices as one composition. The laptop remains dominant; the phone uses roughly 27% of the composition width and overlaps only the laptop's left edge. The hero must not introduce horizontal overflow.

## Verification

- Format and statically analyze the modified Dart file.
- Confirm the metric labels remain absent.
- Confirm both generated assets are registered in `pubspec.yaml`.
- Review the local web build at desktop and mobile widths.