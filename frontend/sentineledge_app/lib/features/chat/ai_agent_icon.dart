import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/app_colors.dart';
import '../../design/app_motion.dart';

/// Brand mascot asset for the Erlang AI Agent.
const aiAgentIconAsset = 'assets/brand/erlang-ai-agent-icon.png';

/// The animated red-blue "aurora" orb used for the AI Agent FAB and the chat
/// empty state. Honours reduced-motion by freezing the animation.
class AnimatedAiAgentIcon extends StatefulWidget {
  const AnimatedAiAgentIcon({super.key, this.size = 88});

  final double size;

  @override
  State<AnimatedAiAgentIcon> createState() => _AnimatedAiAgentIconState();
}

class _AnimatedAiAgentIconState extends State<AnimatedAiAgentIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.reduced(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = reducedMotion ? 0.0 : _controller.value;
        // 0..1 breathing curve that drives the soft pulsing outer glow.
        final breath = 0.5 + 0.5 * math.sin(t * math.pi * 2);
        return SizedBox.square(
          dimension: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Twin coloured glows offset to opposite sides make the whole
              // orb read as a single soft light source, not a flat disc.
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.16 + breath * 0.16),
                  blurRadius: widget.size * (0.24 + breath * 0.14),
                  spreadRadius: widget.size * 0.01,
                  offset: Offset(-widget.size * 0.04, widget.size * 0.06),
                ),
                BoxShadow(
                  color: AppColors.info.withValues(alpha: 0.18 + breath * 0.16),
                  blurRadius: widget.size * (0.28 + breath * 0.16),
                  spreadRadius: widget.size * 0.01,
                  offset: Offset(widget.size * 0.04, widget.size * 0.10),
                ),
              ],
            ),
            child: ClipOval(
              child: CustomPaint(
                painter: _AgentAuroraPainter(progress: t),
                child: Center(
                  // The mascot floats directly on the aurora — its own
                  // transparent bubble shape lets the glow show through.
                  child: AiAgentIconMark(size: widget.size * 0.74),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A calm "liquid aurora" background: a dark glass disc lit from within by two
/// drifting pools of light — one red, one blue — blended additively so where
/// they overlap the light brightens toward magenta/white instead of muddying.
class _AgentAuroraPainter extends CustomPainter {
  const _AgentAuroraPainter({required this.progress});

  final double progress;

  static const _red = Color(0xFFF03A24);
  static const _blue = Color(0xFF2E6BF0);
  static const _spark = Color(0xFFFF4D7D);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;
    final phase = progress * math.pi * 2;
    final breath = 0.5 + 0.5 * math.sin(phase);
    final drift = math.sin(phase);

    // 1. Dark glass base so the coloured light reads as a glow.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF17213B), Color(0xFF080B14)],
          stops: [0.0, 1.0],
        ).createShader(rect),
    );

    // Keep every glow contained within the disc.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    void glow(double angle, double dist, double blobRadius, Color color, double alpha) {
      final c = center + Offset(math.cos(angle) * dist, math.sin(angle) * dist);
      final r = Rect.fromCircle(center: c, radius: blobRadius);
      canvas.drawCircle(
        c,
        blobRadius,
        Paint()
          ..blendMode = BlendMode.plus // additive: overlaps brighten, never mud
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
            stops: const [0.0, 1.0],
          ).createShader(r),
      );
    }

    // 2. Red and blue pools drifting on opposite sides, breathing in size.
    glow(phase * 0.9, radius * (0.34 + 0.08 * drift),
        radius * (0.82 + 0.10 * breath), _red, 0.80);
    glow(phase * 0.9 + math.pi + 0.5, radius * (0.36 - 0.08 * drift),
        radius * (0.84 + 0.10 * (1 - breath)), _blue, 0.82);
    // A small mingling spark keeps the centre alive without clutter.
    glow(-phase * 0.6, radius * 0.16 * drift,
        radius * (0.42 + 0.08 * breath), _spark, 0.28);

    // 3. Glassy specular highlight, upper-left.
    final hl = center + Offset(-radius * 0.30, -radius * 0.34);
    canvas.drawCircle(
      hl,
      radius * 0.60,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.20), Colors.white.withValues(alpha: 0)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: hl, radius: radius * 0.60)),
    );

    // 4. Gentle light lift behind the mascot so its dark outline stays legible.
    canvas.drawCircle(
      center,
      radius * 0.52,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 0.52)),
    );

    // 5. A soft highlight arc sweeping the rim — definition without a hard ring.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.26),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.12, 0.36, 1.0],
          transform: GradientRotation(phase),
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AgentAuroraPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// The static mascot mark on its own, without the animated aurora.
class AiAgentIconMark extends StatelessWidget {
  const AiAgentIconMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        aiAgentIconAsset,
        fit: BoxFit.contain,
        semanticLabel: 'Erlang AI Agent',
      ),
    );
  }
}
