import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_colors.dart';
import '../design/app_motion.dart';
import '../design/app_shadows.dart';
import '../design/app_spacing.dart';
import '../design/app_typography.dart';

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

/// Small rounded-square icon container used in headers, tiles, and lists.
class IconChip extends StatelessWidget {
  const IconChip({
    required this.icon,
    this.color,
    this.background,
    this.size = 36,
    super.key,
  });

  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? fg.withValues(alpha: 0.12),
        borderRadius: AppRadius.mdAll,
      ),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}

/// A surface card: white fill, soft shadow, large radius. Optional hover lift
/// for pointer devices.
class AppCard extends StatefulWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.onTap,
    this.selected = false,
    this.hoverable = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  final bool hoverable;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lifted = widget.hoverable && _hovered;
    final content = AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.fast),
      curve: AppMotion.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: widget.selected
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: widget.selected ? 1.4 : 1,
        ),
        boxShadow: lifted
            ? AppShadows.raised(theme.brightness)
            : AppShadows.card(theme.brightness),
      ),
      child: widget.child,
    );

    if (widget.onTap == null && !widget.hoverable) return content;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(onTap: widget.onTap, child: content),
    );
  }
}

/// Title row with optional icon chip, subtitle, and trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[IconChip(icon: icon!), AppSpacing.hMd],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[AppSpacing.hSm, trailing!],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Panels & metrics
// ---------------------------------------------------------------------------

/// Section container: header (icon + title + optional action) over content.
class ConsolePanel extends StatelessWidget {
  const ConsolePanel({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackHeader = action != null && constraints.maxWidth < 360;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: title,
                icon: icon,
                subtitle: subtitle,
                trailing: stackHeader ? null : action,
              ),
              if (stackHeader) ...[
                const SizedBox(height: AppSpacing.md),
                Align(alignment: Alignment.centerLeft, child: action!),
              ],
              const SizedBox(height: AppSpacing.lg),
              child,
            ],
          );
        },
      ),
    );
  }
}

/// Headline metric with an accent icon chip and tabular number.
class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.caption,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = accent ?? scheme.primary;
    return AppCard(
      hoverable: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconChip(icon: icon, color: color, size: 34),
              const Spacer(),
              if (caption != null)
                Text(
                  caption!,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppTypography.tabular(
                  theme.textTheme.headlineMedium ?? const TextStyle(),
                ),
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

/// Pill that communicates state. Prefer [tone] (semantic) over a raw [color].
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    this.tone,
    this.color,
    this.dot = true,
    this.icon,
    super.key,
  }) : assert(tone != null || color != null, 'Provide a tone or a color');

  /// Convenience: derive the tone from a status string.
  StatusPill.fromStatus(String status, {Key? key})
    : this(label: status, tone: StatusToneColor.fromStatus(status), key: key);

  final String label;
  final StatusTone? tone;
  final Color? color;
  final bool dot;

  /// Optional leading glyph. When set, it replaces the status [dot] — use for
  /// states that deserve a distinct mark (e.g. a verified badge).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.extension<AppStatusColors>();
    final resolvedTone = tone;
    final fg =
        color ?? (status?.foreground(resolvedTone!) ?? resolvedTone!.base);
    final bg = color != null
        ? color!.withValues(alpha: 0.12)
        : (status?.background(resolvedTone!) ??
              resolvedTone!.base.withValues(alpha: 0.12));
    final bd = color != null
        ? color!.withValues(alpha: 0.28)
        : (status?.border(resolvedTone!) ??
              resolvedTone!.base.withValues(alpha: 0.28));

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: bd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ] else if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum AppButtonVariant { primary, secondary, text }

/// Button wrapper with a built-in loading state and consistent icon spacing.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.variant = AppButtonVariant.primary,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final String? loadingLabel;
  final AppButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = loading ? null : onPressed;
    final text = loading ? (loadingLabel ?? label) : label;
    final leading = loading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : (icon != null ? Icon(icon, size: 18) : null);

    Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
        button = leading != null
            ? FilledButton.icon(
                onPressed: effectiveOnPressed,
                icon: leading,
                label: Text(text),
              )
            : FilledButton(onPressed: effectiveOnPressed, child: Text(text));
      case AppButtonVariant.secondary:
        button = leading != null
            ? OutlinedButton.icon(
                onPressed: effectiveOnPressed,
                icon: leading,
                label: Text(text),
              )
            : OutlinedButton(onPressed: effectiveOnPressed, child: Text(text));
      case AppButtonVariant.text:
        button = leading != null
            ? TextButton.icon(
                onPressed: effectiveOnPressed,
                icon: leading,
                label: Text(text),
              )
            : TextButton(onPressed: effectiveOnPressed, child: Text(text));
    }
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selectable list tile
// ---------------------------------------------------------------------------

class SelectableConsoleTile extends StatefulWidget {
  const SelectableConsoleTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leading,
    this.trailing,
    this.stackedTrailing,
    super.key,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? leading;

  /// Stays pinned to the right edge in every layout (e.g. an edit affordance).
  final Widget? trailing;

  /// Secondary trailing content (e.g. a status pill). On narrow/mobile widths
  /// it drops below the text so the title/subtitle keep the full width; on wide
  /// layouts it sits inline to the right, before [trailing].
  final Widget? stackedTrailing;

  @override
  State<SelectableConsoleTile> createState() => _SelectableConsoleTileState();
}

class _SelectableConsoleTileState extends State<SelectableConsoleTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final bg = selected
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : _hovered
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: AppMotion.duration(context, AppMotion.fast),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.45)
                      : scheme.outlineVariant,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // On narrow (mobile) rows, drop the secondary trailing content
                  // under the text so the title/subtitle keep the full width.
                  final stack =
                      widget.stackedTrailing != null &&
                      constraints.maxWidth < 420;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left accent bar communicates selection without a heavy border.
                      AnimatedContainer(
                        duration: AppMotion.duration(context, AppMotion.fast),
                        width: 3,
                        height: 34,
                        margin: const EdgeInsets.only(right: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : Colors.transparent,
                          borderRadius: AppRadius.pillAll,
                        ),
                      ),
                      if (widget.leading != null) ...[
                        widget.leading!,
                        AppSpacing.hMd,
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            if (stack) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: widget.stackedTrailing!,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.stackedTrailing != null && !stack) ...[
                        AppSpacing.hMd,
                        widget.stackedTrailing!,
                      ],
                      if (widget.trailing != null) ...[
                        AppSpacing.hMd,
                        widget.trailing!,
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Code / token surfaces
// ---------------------------------------------------------------------------

/// One-time edge token, shown in a dark "secret" surface with a copy action.
class TokenBox extends StatelessWidget {
  const TokenBox({required this.token, super.key});

  final String token;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1512),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: const Color(0xFF1E4A3F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.key_outlined,
                size: 16,
                color: Color(0xFF8FE3CB),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'One-time edge token — copy it now',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF8FE3CB),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _CopyIconButton(
                value: token,
                tooltip: 'Copy token',
                color: const Color(0xFF8FE3CB),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(token, style: AppTypography.mono(color: Colors.white)),
        ],
      ),
    );
  }
}

/// Monospace block for JSON / structured data, with an optional copy action.
class CodeBlock extends StatelessWidget {
  const CodeBlock({required this.label, required this.value, super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = value ?? 'not provided';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            text,
            style: AppTypography.mono(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Inline alert / banner driven by a semantic tone.
class AppBanner extends StatelessWidget {
  const AppBanner({
    required this.text,
    this.tone = StatusTone.danger,
    this.icon,
    super.key,
  });

  final String text;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.extension<AppStatusColors>();
    final fg = status?.foreground(tone) ?? tone.base;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: status?.background(tone) ?? tone.base.withValues(alpha: 0.12),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: status?.border(tone) ?? tone.base.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.error_outline, size: 18, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyIconButton extends StatelessWidget {
  const _CopyIconButton({
    required this.value,
    required this.tooltip,
    this.color,
  });

  final String value;
  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      color: color,
      iconSize: 18,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
      },
      icon: const Icon(Icons.copy_rounded),
    );
  }
}

/// Public copy button used by detail panels (e.g. playback URL).
class CopyIconButton extends StatelessWidget {
  const CopyIconButton({required this.value, required this.tooltip, super.key});

  final String value;
  final String tooltip;

  @override
  Widget build(BuildContext context) =>
      _CopyIconButton(value: value, tooltip: tooltip);
}

// ---------------------------------------------------------------------------
// Skeleton loaders
// ---------------------------------------------------------------------------

/// Shimmering placeholder block. Falls back to a static block under reduced
/// motion.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    this.width = double.infinity,
    this.height = 16,
    this.radius = AppRadius.sm,
    super.key,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = scheme.surfaceContainerHigh;
    final highlight = scheme.surfaceContainerLowest;
    final box = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(width: widget.width, height: widget.height),
    );

    if (AppMotion.reduced(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: box,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * t, 0),
              end: Alignment(1 - 2 * t, 0),
              colors: [baseColor, highlight, baseColor],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
          child: box,
        );
      },
    );
  }
}

/// A few skeleton rows that mimic the shape of a list while it loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.rows = 3, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        rows,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: SkeletonBox(height: 62, radius: AppRadius.md),
        ),
      ),
    );
  }
}

