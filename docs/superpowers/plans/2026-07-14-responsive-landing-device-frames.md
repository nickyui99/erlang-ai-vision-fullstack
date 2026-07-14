# Laptop and Mobile Landing Preview Implementation Plan

**Goal:** Add the supplied Erlang AI Agent mobile screen beside the enlarged laptop while retaining the original live console and removing the metric row.

## Changes

- Generate a graphite phone cutout from the user-supplied mobile screenshot using built-in imagegen.
- Remove its chroma key into `assets/landing/mobile-agent-frame.png`.
- Register the phone asset in `pubspec.yaml`.
- Extract the existing laptop preview into a reusable nested widget.
- Compose an enlarged laptop at the right and a bottom-aligned phone overlapping its left edge.
- Keep the live laptop console and existing hero behavior unchanged.

## Verification

- Run Dart formatting and static analysis.
- Run `git diff --check`.
- Do not run Flutter tests per user request.
- Do not push or merge before user approval.