# Landing Device Frames Design

**Date:** 2026-07-14  
**Status:** Approved visual direction

## Goal

Shorten the first landing section and present the product as a responsive desktop-and-mobile system without weakening the judge-facing EdgeAgent story.

## Approved composition

- Remove the full static metric strip: Online cameras, Armed agents, and Qwen verdicts.
- Place the existing desktop console preview inside a realistic Flutter laptop frame.
- Add a narrower mobile product preview inside a Flutter iPhone frame.
- Overlap the iPhone over the laptop's lower-right edge on wide layouts.
- Keep the laptop visually dominant because it explains camera perception, protection-agent configuration, and Qwen audit activity.
- Use the iPhone to show the mobile monitoring/control experience rather than duplicating all desktop content.

## Responsive behavior

- Wide desktop: laptop and overlapping iPhone form one compact hero illustration.
- Medium width: reduce overlap and scale both devices without clipping.
- Narrow/mobile: stack the laptop above the iPhone, center both, and preserve readable controls.
- The first landing section must not gain horizontal scrolling.

## Content hierarchy

1. Hero headline and primary actions.
2. Laptop live-camera console.
3. iPhone mobile status/control preview.
4. Protection-agent and audit details within the device presentation.

The removed metric values must not be relocated elsewhere in the hero.

## Implementation boundaries

- Reuse existing Flutter assets, colors, spacing, and animation.
- Build frames with Flutter layout and decoration primitives; add no image-frame dependency.
- Keep navigation and button behavior unchanged.
- Limit changes to the landing preview and directly related widget tests.

## Verification

- Run Flutter formatting, static analysis, and widget tests.
- Check wide, medium, and narrow constraints for overflow.
- Confirm metric labels no longer render.
- Confirm laptop and iPhone frames remain visible and camera/agent/audit content is retained.