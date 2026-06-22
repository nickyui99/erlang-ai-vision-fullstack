# SentinelEdge — UI/UX Redesign Plan

**Direction:** Modern SaaS / clean light (Linear / Notion / Vercel lineage)
**Scope:** Design system + full re-skin
**Platform:** Fully responsive (web/desktop and mobile both first-class)
**Stack:** Flutter, Material 3 (`useMaterial3: true`)

---

## 1. Design principles (the rules we hold every screen to)

1. **Clarity over decoration.** Every pixel earns its place. Whitespace is a feature, not waste.
2. **One clear hierarchy per screen.** A single primary action, supporting info recedes (size, weight, color).
3. **Soft, calm surfaces.** Light neutral background, white cards, soft shadows instead of hard borders. Depth communicates grouping.
4. **Semantic, restrained color.** Neutral 90% of the time; color reserved for state (online/armed/error) and the single primary action.
5. **Consistent rhythm.** All spacing, radius, and type sizes come from a fixed scale — never ad-hoc numbers.
6. **Responsive by construction.** Layout adapts at defined breakpoints; touch targets and density adjust per platform.
7. **Motion with meaning.** State changes animate (150–250ms) to explain what happened; never gratuitous.
8. **Accessible by default.** WCAG AA contrast, 44px+ targets, focus states, semantic labels.

---

## 2. Current-state assessment

What exists today ([sentineledge_theme.dart](../lib/app/sentineledge_theme.dart), [console_widgets.dart](../lib/shared/console_widgets.dart), [workspace_view.dart](../lib/features/dashboard/workspace_view.dart), [auth_shell.dart](../lib/features/auth/auth_shell.dart)):

| Area | Today | Gap for "clean SaaS" |
|------|-------|----------------------|
| Type | Default system font, weights hardcoded as `w800` everywhere | No type scale, no custom font, over-bold |
| Color | Single seed `0xFF2F6B5F`, status colors hardcoded inline in 3+ places | No semantic token layer, duplication, dark-leaning teal reads heavy in light mode |
| Surfaces | Flat cards, 8px radius, hard 0.7-alpha borders, `elevation: 0` | No soft-shadow depth, corners too tight for SaaS |
| Spacing | Inline `SizedBox`/`EdgeInsets` magic numbers (10,12,14,16,20) | No spacing scale |
| Motion | None | No transitions, no feedback animation |
| Components | Good bones (`ConsolePanel`, `MetricTile`, `StatusPill`, `EmptyState`, `SelectableConsoleTile`) | Need restyle + a few new ones (buttons, skeletons, badges) |
| Feedback | `SnackBar` + inline error banner; spinners inline | No skeleton loaders, no toast styling, abrupt empty/loading states |
| Layout | `NavigationRail`/`NavigationBar`, single 760 breakpoint, max width 1180 | Need richer breakpoint system + refined nav |

**Strengths to keep:** the component decomposition is solid, responsive `LayoutBuilder` pattern is already in place, `_run()` busy/error handling is clean. We re-skin on top of this skeleton rather than rewrite logic.

---

## 3. The design system (foundation layer)

Create `lib/design/` as the single source of truth. **No widget hardcodes a color, size, or radius again** — everything references these.

```
lib/design/
  app_colors.dart      # raw palette + semantic roles
  app_spacing.dart     # 4pt spacing + radius + breakpoints
  app_typography.dart  # type scale (TextTheme)
  app_shadows.dart     # elevation tokens (soft shadows)
  app_motion.dart      # durations + curves
  app_theme.dart       # assembles ThemeData (replaces sentineledge_theme.dart)
```

### 3.1 Color — clean light SaaS palette

- **Neutrals (the workhorse):** a true neutral gray ramp `50→900` for backgrounds, surfaces, borders, text. Background `#FAFAFA`/`#F7F8FA`, cards pure white, hairline borders `#ECECEF`.
- **Brand primary:** evolve the teal into a cleaner, slightly brighter `#0E9F6E`-family (or keep `#2F6B5F` as the deep brand and add a brighter interactive primary). Used for the *one* primary action + selection.
- **Semantic state tokens (replace the inline `_statusColor` switch):**
  - `success` (online / armed / active) — green
  - `warning` (connecting / degraded / pending) — amber
  - `danger` (offline / error / disabled) — red
  - `info` (neutral status) — blue/slate
  - Each gets `fg`, `bg` (soft tint), `border` variants → powers `StatusPill`, badges, banners consistently.
- Define both light and a future-proofed dark map, but **ship light first** (per chosen direction). Keep `ThemeMode.system` working.

### 3.2 Spacing & shape — 4pt scale

```dart
class AppSpacing { static const xs=4, sm=8, md=12, lg=16, xl=24, xxl=32, xxxl=48; }
class AppRadius  { static const sm=8, md=12, lg=16, pill=999; }   // SaaS = 12–16, not 8
class AppBreakpoints { static const compact=640, medium=1024, expanded=1440; }
```

### 3.3 Typography — custom font + real scale

- Add **Inter** (or Geist/Plus Jakarta Sans) via `google_fonts` or bundled assets.
- Define a proper `TextTheme`: `displaySmall / headlineSmall / titleLarge / titleMedium / bodyLarge / bodyMedium / labelLarge / labelSmall` with deliberate sizes, line-heights, and **moderate** weights (400/500/600/700 — kill the blanket `w800`).
- Numerals: tabular figures for metric tiles and data tables.

### 3.4 Elevation — soft shadows, not borders

Replace hard 0.7-alpha borders with layered soft shadows:
```dart
class AppShadows {
  static const card = [BoxShadow(blurRadius:1,offset:Offset(0,1),color: black.04),
                       BoxShadow(blurRadius:3,offset:Offset(0,1),color: black.06)];
  static const raised = [...bigger blur for menus/dialogs/toasts];
}
```
Cards: white fill + `card` shadow + 1px ultra-light border for crispness.

### 3.5 Motion

```dart
class AppMotion {
  static const fast=Duration(ms:120), base=Duration(ms:200), slow=Duration(ms:320);
  static const easeOut = Curves.easeOutCubic; static const emphasized = Curves.easeOutQuint;
}
```
Used for tab/content switches (`AnimatedSwitcher`), tile selection, pill state changes, hover.

---

## 4. Component library upgrade

Re-skin existing shared widgets against the new tokens; add a few primitives.

| Component | Change |
|-----------|--------|
| `ConsolePanel` → `AppCard`/`SectionCard` | White surface, soft shadow, 16px radius, refined header (icon chip lighter, title `titleMedium w600`), optional subtitle + trailing action slot |
| `MetricTile` → `StatCard` | Larger number (tabular), label above/below, trend/delta line optional, subtle hover lift on web, accent reduced to a small icon chip + thin top accent |
| `StatusPill` → `StatusBadge` | Drive from semantic tokens (success/warning/danger/info), add optional leading dot, sentence-case labels |
| `SelectableConsoleTile` → `ListTileCard` | Softer selected state (tinted bg + left accent bar instead of full border swap), hover state, better trailing alignment |
| `EmptyState` | Centered, illustration/icon-in-circle, title + body + optional primary CTA button |
| `TokenBox` | Keep dark "code" treatment but align radius/spacing; add explicit Copy button + "shown once" warning styling |
| **New:** `AppButton` set | Wrap FilledButton/Outlined/Text with consistent sizing, loading state, icon spacing |
| **New:** `SkeletonLoader` | Shimmer placeholders for cards/lists/metrics during fetch (replaces bare spinners) |
| **New:** `AppToast`/snackbar theme | Styled, semantic-colored, icon + message, auto-dismiss |
| **New:** `SectionHeader` | Title + description + actions row, reused across panels |
| **New:** `PageScaffold` | Standard padded, max-width, scrollable content shell (extract from `_WorkspaceBody`) |

---

## 5. Screen-by-screen re-skin

### 5.1 App shell / navigation ([workspace_view.dart](../lib/features/dashboard/workspace_view.dart))
- **Desktop:** refined `NavigationRail` → a proper left sidebar: brand lockup at top, grouped destinations, user avatar + sign-out pinned at bottom. Selection = pill highlight + accent.
- **Mobile:** keep `NavigationBar` (bottom), restyle with the token set, larger touch targets.
- **Top bar:** cleaner — page title + breadcrumb/subtitle, realtime status as a refined dot+label chip, refresh and account as icon buttons with consistent sizing.
- Animate content area on tab switch (`AnimatedSwitcher` + fade/slide).
- Breakpoints: `<640` bottom nav stacked; `640–1024` rail collapsed (icons); `≥1024` rail extended (icons + labels); content max-width ~1240 centered.

### 5.2 Overview / dashboard
- Top row: 4 `StatCard`s in a responsive grid (1→2→4 columns), with subtle accent + icon, tabular numbers.
- Below: "Operational focus" and "Edge sync state" as `SectionCard`s; richer empty states with CTAs.
- Add small live indicators (animated pulse dot for "Live").

### 5.3 Devices & 5.4 Agents (the `_responsivePair` screens)
- Left: form card (register device / create agent) — grouped fields, helper text, clear primary button with loading state.
- Right: searchable roster — `ListTileCard` rows, status badges, hover, selected accent bar, skeletons while loading, illustrated empty/no-match states.
- Mobile stacks form → list (already does; just restyle + spacing).

### 5.5 Events
- Master/detail: list of events (severity badge, time, device/agent) + detail panel.
- Detail: clean key/value layout, severity/status badges row, **collapsible** stage-result JSON in a styled code block (monospace, copy button), clips list with playback action, styled playback-URL card with copy + expiry.

### 5.6 Edge
- Token field with show/hide + paste helper, action buttons with loading states, synced-config list as `ListTileCard`s, strong empty state.

### 5.7 Auth / Sign-in ([auth_shell.dart](../lib/features/auth/auth_shell.dart))
- Keep the split brand/login layout — it's strong. Re-skin: brand panel gets a subtle gradient/mesh background, larger logo lockup, feature pills restyled; login panel cleaner with the new button + alert components. Card gets soft shadow + 16px radius. Smooth loading transition.

---

## 6. Accessibility & polish pass
- Verify AA contrast for all text/badge combos against light surfaces.
- Focus rings for keyboard nav (web), `Semantics` labels on icon-only buttons (already have tooltips — good).
- Min 44×44 touch targets on mobile.
- Respect reduced-motion (gate animations on `MediaQuery.disableAnimations`).
- Empty, loading, and error states designed for *every* async surface (no bare spinners).

---

## 7. Dependencies to add
```yaml
google_fonts: ^6.x        # Inter / Geist (or bundle TTFs to avoid runtime fetch)
# optional:
flutter_animate: ^4.x     # concise micro-animations
shimmer: ^3.x             # skeleton loaders (or hand-roll)
```
> If offline/locked-down builds matter, bundle the font as an asset instead of `google_fonts` runtime fetch.

---

## 8. Phased execution

**Phase 0 — Foundation (no visible change yet)**
1. Create `lib/design/` tokens (color, spacing, type, shadow, motion).
2. Build `app_theme.dart`; wire into [sentineledge_app.dart](../lib/app/sentineledge_app.dart), retire `sentineledge_theme.dart`.
3. Add font dependency + `TextTheme`.
*Checkpoint: app builds, looks slightly different, nothing broken.*

**Phase 1 — Component library**
4. Re-skin shared widgets to tokens; add `AppButton`, `SkeletonLoader`, `SectionHeader`, `PageScaffold`, toast theme.
5. Replace inline `_statusColor` with semantic tokens.
*Checkpoint: every screen inherits the new look via shared widgets.*

**Phase 2 — Shell & navigation**
6. Sidebar/topbar redesign + responsive breakpoints + content transition.

**Phase 3 — Screen re-skins**
7. Overview → Devices → Agents → Events → Edge → Auth (one PR each, in this order).

**Phase 4 — Motion, skeletons, a11y**
8. Loading skeletons, state-change animations, accessibility + reduced-motion pass.

**Phase 5 — QA**
9. Test at all breakpoints (mobile / tablet / desktop), light+dark, keyboard nav; update `widget_test.dart`.

---

## 9. Definition of done
- Zero hardcoded colors/sizes/radii outside `lib/design/`.
- Consistent type scale and spacing rhythm across all screens.
- Every async surface has loading + empty + error states.
- Works cleanly at 360px, 768px, 1024px, 1440px+.
- AA contrast verified; keyboard + reduced-motion supported.
- Cohesive "clean SaaS" feel: white cards, soft shadows, calm neutrals, one confident accent.
