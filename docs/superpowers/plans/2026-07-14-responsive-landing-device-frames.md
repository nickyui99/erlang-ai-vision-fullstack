# Single Laptop Landing Preview Implementation Plan

**Goal:** Restore the original single-console landing preview, remove the static metric row, and frame it with a generated transparent laptop asset.

## Changes

- Restore the pre-phone landing console composition.
- Generate a front-facing chroma-key laptop product render using the built-in image generator.
- Remove the chroma key locally to create `assets/landing/laptop-frame.png`.
- Register the asset in `pubspec.yaml`.
- Render the original desktop console behind the transparent screen aperture.
- Remove the metric strip and its unused metric widget.
- Remove all phone-frame and side-by-side responsive code.

## Verification

- Run Dart formatting.
- Run static analysis on `landing_page.dart`.
- Run `git diff --check`.
- Launch the local Flutter web server for visual review.
- Do not run Flutter tests per user request.
- Do not push or merge before user approval.