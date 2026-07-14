# Landing Laptop Frame Design

**Date:** 2026-07-14  
**Status:** Approved revised direction

## Goal

Keep the original single-console hero composition, shorten it by removing the static metric row, and present the console inside a polished laptop frame.

## Final composition

- Keep one desktop console preview; do not add a phone preview.
- Remove Online cameras, Armed agents, and Qwen verdicts from the hero.
- Preserve the live camera, Protection agent, audit activity, and camera controls.
- Use the generated transparent laptop shell at `assets/landing/laptop-frame.png`.
- Render the live Flutter console beneath the transparent screen opening.
- Keep navigation and hero actions unchanged.

## Asset requirements

The laptop is a front-facing dark graphite product render with no logo, text, watermark, baked-in UI, shadow, or background. Both the exterior and screen were generated on chroma key and converted to alpha so the asset functions as an overlay.

## Responsive behavior

Scale the laptop and live console together as one 3:2 composition. The landing page must not introduce horizontal overflow. The console remains readable through a fitted fixed design surface.

## Verification

- Format and statically analyze the modified Dart file.
- Confirm the three metric labels and all phone-frame widgets are absent.
- Confirm the generated image is registered in `pubspec.yaml`.
- Review the live web build at desktop and mobile widths.