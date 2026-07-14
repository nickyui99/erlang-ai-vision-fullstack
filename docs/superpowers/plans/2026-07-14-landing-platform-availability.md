# Landing Platform Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compact Android, Web, and iOS availability chips directly below the landing hero buttons.

**Architecture:** Extend the private `_HeroCopy` column with a delayed reveal containing a responsive `Wrap`. A private `_PlatformAvailabilityChip` owns icon, platform, status, and tone styling so each entry uses one consistent interface.

**Tech Stack:** Flutter, Dart, Material icons, existing AppColors/AppSpacing/AppRadius tokens.

## Global Constraints

- Android and Web display Available.
- iOS displays Coming soon with a muted neutral tone.
- Add no routes, links, dependencies, images, analytics, or new landing section.
- Preserve CTA behavior and the laptop/mobile hero.
- Do not run Flutter tests, push, or merge before user review.

---

### Task 1: Add hero platform availability chips

**Files:**
- Modify: `frontend/sentineledge_app/lib/features/landing/landing_page.dart`

**Interfaces:**
- Consumes: existing `_HeroCopy`, `_Reveal`, `AppColors`, `AppSpacing`, and Material `Icons`.
- Produces: private `_PlatformAvailabilityChip({required IconData icon, required String platform, required String status, required Color tone})`.

- [ ] **Step 1: Add the responsive row below the CTA reveal**

Insert after the current CTA reveal:

~~~dart
const SizedBox(height: AppSpacing.lg),
const _Reveal(
  delay: Duration(milliseconds: 380),
  child: Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      _PlatformAvailabilityChip(
        icon: Icons.android,
        platform: 'Android',
        status: 'Available',
        tone: AppColors.success,
      ),
      _PlatformAvailabilityChip(
        icon: Icons.language,
        platform: 'Web',
        status: 'Available',
        tone: AppColors.success,
      ),
      _PlatformAvailabilityChip(
        icon: Icons.apple,
        platform: 'iOS',
        status: 'Coming soon',
        tone: AppColors.neutral400,
      ),
    ],
  ),
),
~~~

- [ ] **Step 2: Add the reusable chip widget**

~~~dart
class _PlatformAvailabilityChip extends StatelessWidget {
  const _PlatformAvailabilityChip({
    required this.icon,
    required this.platform,
    required this.status,
    required this.tone,
  });

  final IconData icon;
  final String platform;
  final String status;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Text(platform),
          const SizedBox(width: 6),
          Text(status, style: TextStyle(color: tone)),
        ],
      ),
    );
  }
}
~~~

- [ ] **Step 3: Format and statically analyze**

~~~powershell
dart format frontend/sentineledge_app/lib/features/landing/landing_page.dart
dart analyze frontend/sentineledge_app/lib/features/landing/landing_page.dart
git diff --check
~~~

Expected: no formatter changes remaining, no analyzer issues, and no whitespace errors.

- [ ] **Step 4: Commit locally**

~~~powershell
git add frontend/sentineledge_app/lib/features/landing/landing_page.dart docs/superpowers/plans/2026-07-14-landing-platform-availability.md
git commit -m "feat: show supported platforms on landing hero"
~~~