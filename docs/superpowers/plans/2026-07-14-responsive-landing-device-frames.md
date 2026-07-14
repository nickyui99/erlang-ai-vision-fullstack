# Responsive Landing Device Frames Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the landing hero's static metric strip with an overlapping laptop-and-iPhone product preview that remains usable at narrow widths.

**Architecture:** Keep the public `LandingPage` interface unchanged. Refactor only the private preview composition in `landing_page.dart`: a laptop frame wraps the existing desktop preview content, an iPhone frame hosts a concise mobile preview, and the outer responsive composer switches from overlap to vertical stacking. Focused widget tests assert removed metrics, retained product content, frame semantics, and no overflow at representative widths.

**Tech Stack:** Flutter, Dart, Material widgets, flutter_test.

## Global Constraints

- Work only on local branch `feat/landing-device-frames`; do not push or merge to `main` before user review.
- Remove Online cameras, Armed agents, and Qwen verdicts from the hero.
- Use Flutter layout/decoration primitives and existing assets; add no dependency.
- Preserve navigation and hero button behavior.
- Wide screens overlap the iPhone at the laptop's lower-right; narrow screens stack devices without horizontal overflow.

---

### Task 1: Add responsive landing-preview contract tests

**Files:**
- Modify: `frontend/sentineledge_app/test/widget_test.dart`
- Test: `frontend/sentineledge_app/test/widget_test.dart`

**Interfaces:**
- Consumes: public `LandingPage` constructor.
- Produces: regression coverage for frame keys `landing-laptop-frame` and `landing-phone-frame`, removed metrics, retained camera/agent/audit content, and overflow-free narrow rendering.

- [ ] **Step 1: Add a landing host helper and wide-screen failing test**

Add:

~~~dart
Widget _landingHost() {
  return const MaterialApp(
    home: LandingPage(),
  );
}

testWidgets('landing hero uses laptop and phone frames without vanity metrics', (
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(_landingHost());
  await tester.pump(const Duration(seconds: 1));

  expect(find.byKey(const ValueKey('landing-laptop-frame')), findsOneWidget);
  expect(find.byKey(const ValueKey('landing-phone-frame')), findsOneWidget);
  expect(find.text('Online cameras'), findsNothing);
  expect(find.text('Armed agents'), findsNothing);
  expect(find.text('Qwen verdicts'), findsNothing);
  expect(find.text('Front Door'), findsWidgets);
  expect(find.text('Protection agent'), findsWidgets);
});
~~~

- [ ] **Step 2: Add a narrow-screen overflow test**

Add:

~~~dart
testWidgets('landing device frames stack without overflow on mobile', (
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(_landingHost());
  await tester.pump(const Duration(seconds: 1));

  expect(find.byKey(const ValueKey('landing-laptop-frame')), findsOneWidget);
  expect(find.byKey(const ValueKey('landing-phone-frame')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
~~~

- [ ] **Step 3: Run the focused tests and verify failure**

Run from `frontend/sentineledge_app`:

~~~powershell
flutter test test/widget_test.dart --plain-name "landing"
~~~

Expected: FAIL because the frame keys do not exist and current compact layout may overflow after the new expectations.

- [ ] **Step 4: Commit the failing tests**

~~~powershell
git add frontend/sentineledge_app/test/widget_test.dart
git commit -m "test: define responsive landing device frames"
~~~

### Task 2: Replace the metric strip with framed desktop and mobile previews

**Files:**
- Modify: `frontend/sentineledge_app/lib/features/landing/landing_page.dart`
- Test: `frontend/sentineledge_app/test/widget_test.dart`

**Interfaces:**
- Consumes: existing private widgets `_PreviewHeader`, `_CameraPreviewCard`, `_AgentPreviewCard`, and `_AuditPreviewCard`.
- Produces: private `_LaptopFrame`, `_PhoneFrame`, `_DesktopPreviewContent`, `_MobilePreviewContent`, and responsive `_ConsolePreview`.

- [ ] **Step 1: Remove the metric strip class and its call sites**

Delete `_MetricStrip` and all `_MiniMetric` uses that exist only for it. Do not relocate its three labels.

- [ ] **Step 2: Extract desktop and mobile preview content**

Implement a desktop content widget that retains header, live camera, Protection agent, and audit cards without the metric row. Implement a concise mobile content widget with Front Door live state, camera image, Protection agent state, and Snapshot/Pan/Tilt controls.

~~~dart
class _DesktopPreviewContent extends StatelessWidget {
  const _DesktopPreviewContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 72, child: _PreviewRail()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                const _PreviewHeader(),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: Row(
                    children: [
                      const Expanded(flex: 7, child: _CameraPreviewCard()),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: const [
                            Expanded(child: _AgentPreviewCard()),
                            SizedBox(height: AppSpacing.md),
                            Expanded(child: _AuditPreviewCard()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
~~~

- [ ] **Step 3: Build laptop and iPhone frame widgets**

Give frames stable semantic keys and construct them with rounded containers, borders, shadows, a laptop base/hinge, and a phone notch/home indicator.

~~~dart
class _LaptopFrame extends StatelessWidget {
  const _LaptopFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('landing-laptop-frame'),
      children: [
        AspectRatio(
          aspectRatio: 1.45,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF252A33),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: child,
            ),
          ),
        ),
        Container(
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            color: Color(0xFFB8BEC8),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
        ),
      ],
    );
  }
}
~~~

The phone frame uses key `landing-phone-frame`, a dark rounded shell, a centered notch, and a clipped `_MobilePreviewContent`.

- [ ] **Step 4: Compose overlap and stacked variants**

In `_ConsolePreview`, use `LayoutBuilder`:

- below 680px: laptop then phone in a centered `Column`;
- 680px and above: `Stack(clipBehavior: Clip.none)` with laptop using roughly 86% width and phone using roughly 25% width, positioned right and bottom;
- add bottom/right padding around the wide stack so its shadow and overlap are not clipped;
- reduce the prior fixed compact height now that the metric strip is gone.

- [ ] **Step 5: Format and run focused tests**

~~~powershell
dart format lib/features/landing/landing_page.dart test/widget_test.dart
flutter test test/widget_test.dart --plain-name "landing"
~~~

Expected: both landing tests PASS with no overflow exceptions.

- [ ] **Step 6: Run full frontend verification**

~~~powershell
flutter analyze
flutter test
~~~

Expected: analysis reports no issues and all tests pass.

- [ ] **Step 7: Commit implementation**

~~~powershell
git add frontend/sentineledge_app/lib/features/landing/landing_page.dart frontend/sentineledge_app/test/widget_test.dart
git commit -m "feat: frame landing previews for desktop and mobile"
~~~

### Task 3: Review-ready handoff

**Files:**
- Verify only; no production file changes expected.

**Interfaces:**
- Consumes: completed branch commits.
- Produces: local review branch with verification evidence; no push or main merge.

- [ ] **Step 1: Inspect final diff**

~~~powershell
git diff main...HEAD --check
git diff main...HEAD --stat
git status --short
~~~

Expected: clean working tree and changes limited to the design/plan, ignore rule, landing widget, and widget tests.

- [ ] **Step 2: Report review instructions**

Provide the branch name, commits, verification results, and exact local web run command:

~~~powershell
cd frontend/sentineledge_app
flutter run -d chrome
~~~

Explicitly state that nothing was pushed or merged to `main`.