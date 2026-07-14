# Landing Platform Availability Design

**Date:** 2026-07-14  
**Status:** Approved

## Goal

Show supported client platforms near the primary landing-page actions without adding a new section or materially increasing hero height.

## Design

Add one compact responsive row immediately below the Demo Video and Architecture buttons:

- Android — Available
- Web — Available
- iOS — Coming soon

Each item uses a recognizable platform icon, short label, and status text. Android and Web use the existing success tone. iOS uses a neutral muted tone so “Coming soon” cannot be mistaken for availability.

On narrow screens the items wrap cleanly beneath the stacked CTA buttons. The row is informational only: no links, downloads, hover actions, or platform detection.

## Boundaries

- Change only the landing hero and focused documentation.
- Reuse existing Flutter Material icons, colors, spacing, and typography.
- Add no image assets, dependencies, routes, or analytics.
- Preserve the current laptop/mobile device composition and all CTA behavior.

## Verification

- Format and statically analyze `landing_page.dart`.
- Confirm all three platform/status pairs render in source.
- Confirm the row uses Wrap so it cannot cause horizontal overflow.
- Do not run Flutter tests per the current user preference.
- Do not push or merge before user approval.