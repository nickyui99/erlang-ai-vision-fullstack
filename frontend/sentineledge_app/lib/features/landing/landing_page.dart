import 'package:flutter/material.dart';

import '../../design/app_colors.dart';
import '../../design/app_spacing.dart';
import '../../design/app_typography.dart';
import '../../shared/external_link.dart';

const _logoAsset = 'assets/brand/erlang-ai-vision-logo-long-white.png';
const _cameraIconAsset = 'assets/brand/erlang-ai-camera-tile-icon.png';
const _agentIconAsset = 'assets/brand/erlang-ai-agent-icon.png';
const _scenarioAsset = 'assets/landing/edge-ai-scenario.png';
const _architectureFlowAsset =
    'assets/landing/erlang-ai-vision-architecture-flow.png';
const _githubUrl = 'https://github.com/nickyui99/SentinelEdge-Fullstack';
const _iotRepoUrl = 'https://github.com/KennethChua1998/SentinelEdge_IOT';
const _laptopEdgeRepoUrl =
    'https://github.com/KennethChua1998/SentinelEdge_LaptopEdge';

enum LandingSection { hero, architecture, qwen, github }

class LandingPage extends StatefulWidget {
  const LandingPage({
    required this.onLaunchDemo,
    required this.onLogin,
    required this.onViewArchitecture,
    required this.onViewQwen,
    required this.onViewGithub,
    this.initialSection = LandingSection.hero,
    super.key,
  });

  final VoidCallback onLaunchDemo;
  final VoidCallback onLogin;
  final VoidCallback onViewArchitecture;
  final VoidCallback onViewQwen;
  final VoidCallback onViewGithub;
  final LandingSection initialSection;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _architectureKey = GlobalKey();
  final _qwenKey = GlobalKey();
  final _githubKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToInitialSection(),
    );
  }

  @override
  void didUpdateWidget(covariant LandingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToInitialSection(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final compact = width < AppBreakpoints.compact;
            return SingleChildScrollView(
              child: Column(
                children: [
                  _HeroSection(
                    compact: compact,
                    maxWidth: width,
                    onLaunchDemo: widget.onLaunchDemo,
                    onLogin: widget.onLogin,
                    onViewArchitecture: widget.onViewArchitecture,
                    onViewQwen: widget.onViewQwen,
                    onViewGithub: widget.onViewGithub,
                  ),
                  _Reveal(
                    style: _RevealStyle.slideLeft,
                    child: _ProofSection(compact: compact),
                  ),
                  _Reveal(
                    style: _RevealStyle.slideRight,
                    child: _TraditionalVsAgenticSection(compact: compact),
                  ),
                  _Reveal(
                    style: _RevealStyle.slideLeft,
                    child: _ArchitectureSection(
                      key: _architectureKey,
                      compact: compact,
                    ),
                  ),
                  _Reveal(
                    style: _RevealStyle.slideRight,
                    child: _UseCaseImpactSection(compact: compact),
                  ),
                  _Reveal(
                    style: _RevealStyle.slideLeft,
                    child: _AgenticInvestigationSection(
                      key: _qwenKey,
                      compact: compact,
                    ),
                  ),
                  _Reveal(
                    style: _RevealStyle.zoom,
                    child: _ProjectResourcesSection(
                      key: _githubKey,
                      compact: compact,
                    ),
                  ),
                  _Reveal(
                    child: _FooterCta(
                      onLaunchDemo: widget.onLaunchDemo,
                      onLogin: widget.onLogin,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _scrollToInitialSection() {
    final targetContext = switch (widget.initialSection) {
      LandingSection.architecture => _architectureKey.currentContext,
      LandingSection.qwen => _qwenKey.currentContext,
      LandingSection.github => _githubKey.currentContext,
      LandingSection.hero => null,
    };
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.compact,
    required this.maxWidth,
    required this.onLaunchDemo,
    required this.onLogin,
    required this.onViewArchitecture,
    required this.onViewQwen,
    required this.onViewGithub,
  });

  final bool compact;
  final double maxWidth;
  final VoidCallback onLaunchDemo;
  final VoidCallback onLogin;
  final VoidCallback onViewArchitecture;
  final VoidCallback onViewQwen;
  final VoidCallback onViewGithub;

  @override
  Widget build(BuildContext context) {
    final stacked = maxWidth < 1050;
    return Container(
      constraints: BoxConstraints(minHeight: stacked ? 0 : 720),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF080B10), Color(0xFF10161E), Color(0xFF170E0B)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _LandingGrid()),
          Positioned(
            right: compact ? -160 : -90,
            top: compact ? 140 : 80,
            child: const _SignalGlow(size: 420, color: AppColors.primary),
          ),
          Positioned(
            left: compact ? -190 : -120,
            bottom: compact ? 70 : 10,
            child: const _SignalGlow(size: 360, color: AppColors.info),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.contentMaxWidth,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? AppSpacing.lg : AppSpacing.xxl,
                  AppSpacing.xl,
                  compact ? AppSpacing.lg : AppSpacing.xxl,
                  AppSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LandingNav(
                      onLogin: onLogin,
                      onViewArchitecture: onViewArchitecture,
                      onViewQwen: onViewQwen,
                      onViewGithub: onViewGithub,
                    ),
                    SizedBox(height: compact ? AppSpacing.xxxl : 76),
                    if (stacked) ...[
                      _HeroCopy(
                        compact: compact,
                        stacked: true,
                        onLaunchDemo: onLaunchDemo,
                        onViewArchitecture: onViewArchitecture,
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      const _Reveal(
                        delay: Duration(milliseconds: 250),
                        child: _ConsolePreview(),
                      ),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 9,
                            child: _HeroCopy(
                              compact: compact,
                              stacked: false,
                              onLaunchDemo: onLaunchDemo,
                              onViewArchitecture: onViewArchitecture,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxxl),
                          const Expanded(
                            flex: 11,
                            child: _Reveal(
                              delay: Duration(milliseconds: 250),
                              child: _ConsolePreview(),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingNav extends StatelessWidget {
  const _LandingNav({
    required this.onLogin,
    required this.onViewArchitecture,
    required this.onViewQwen,
    required this.onViewGithub,
  });

  final VoidCallback onLogin;
  final VoidCallback onViewArchitecture;
  final VoidCallback onViewQwen;
  final VoidCallback onViewGithub;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final actions = Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: onViewArchitecture,
              child: const Text('Architecture'),
            ),
            TextButton(onPressed: onViewQwen, child: const Text('Qwen')),
            TextButton(onPressed: onViewGithub, child: const Text('Resources')),
            OutlinedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_outlined, size: 18),
              label: const Text('Login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(_logoAsset, height: 34, fit: BoxFit.contain),
              const SizedBox(height: AppSpacing.md),
              actions,
            ],
          );
        }

        return Row(
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(_logoAsset, height: 38, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            actions,
          ],
        );
      },
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.compact,
    required this.stacked,
    required this.onLaunchDemo,
    required this.onViewArchitecture,
  });

  final bool compact;
  final bool stacked;
  final VoidCallback onLaunchDemo;
  final VoidCallback onViewArchitecture;

  @override
  Widget build(BuildContext context) {
    final titleStyle = AppTypography.display(
      compact ? 38 : (stacked ? 44 : 56),
    );
    final bodyStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: AppColors.neutral300,
      fontSize: 17,
      height: 1.55,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Reveal(child: _Eyebrow(label: 'Erlang AI Vision')),
        const SizedBox(height: AppSpacing.lg),
        _Reveal(
          delay: const Duration(milliseconds: 100),
          child: Text(
            'Camera intelligence that\nsees, thinks, and verifies.',
            style: titleStyle,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Reveal(
          delay: const Duration(milliseconds: 200),
          child: Text.rich(
            TextSpan(
              style: bodyStyle,
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _BrushUnderline(
                    text: 'ESP32 cameras',
                    style: bodyStyle,
                  ),
                ),
                const TextSpan(text: ' see, the '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _BrushUnderline(text: 'edge bridge', style: bodyStyle),
                ),
                const TextSpan(text: ' thinks, and '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _BrushUnderline(text: 'Qwen Cloud', style: bodyStyle),
                ),
                const TextSpan(
                  text:
                      ' verifies — only real events reach your team, with no '
                      'more scrubbing through CCTV footage.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _Reveal(
          delay: const Duration(milliseconds: 300),
          child: Builder(
            builder: (context) {
              final demoButton = FilledButton.icon(
                onPressed: onLaunchDemo,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Demo Video'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(160, 52),
                ),
              );
              final archButton = OutlinedButton.icon(
                onPressed: onViewArchitecture,
                icon: const Icon(Icons.account_tree_outlined, size: 20),
                label: const Text('Architecture'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(180, 52),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    demoButton,
                    const SizedBox(height: AppSpacing.md),
                    archButton,
                  ],
                );
              }
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [demoButton, archButton],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConsolePreview extends StatelessWidget {
  const _ConsolePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutral50,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 60,
            offset: const Offset(0, 28),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          if (compact) {
            return SizedBox(
              height: 840,
              child: Container(
                color: AppColors.lightBackground,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    _PreviewHeader(),
                    SizedBox(height: AppSpacing.md),
                    _MetricStrip(),
                    SizedBox(height: AppSpacing.md),
                    Expanded(child: _CameraPreviewCard()),
                    SizedBox(height: AppSpacing.md),
                    _AgentPreviewCard(),
                  ],
                ),
              ),
            );
          }

          return AspectRatio(
            aspectRatio: 1.18,
            child: Row(
              children: [
                Container(
                  width: 92,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: const _PreviewRail(),
                ),
                Expanded(
                  child: Container(
                    color: AppColors.lightBackground,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _PreviewHeader(),
                        const SizedBox(height: AppSpacing.md),
                        const _MetricStrip(),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: Row(
                            children: [
                              const Expanded(
                                flex: 7,
                                child: _CameraPreviewCard(),
                              ),
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
            ),
          );
        },
      ),
    );
  }
}

class _PreviewRail extends StatelessWidget {
  const _PreviewRail();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.videocam_outlined, true),
      (Icons.dashboard_outlined, false),
      (Icons.smart_toy_outlined, false),
      (Icons.timeline_outlined, false),
      (Icons.settings_outlined, false),
    ];
    return Column(
      children: [
        Image.asset(_cameraIconAsset, width: 42, height: 42),
        const SizedBox(height: AppSpacing.xl),
        for (final item in items)
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: item.$2 ? AppColors.primaryContainer : Colors.transparent,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(
              item.$1,
              color: item.$2 ? AppColors.primary : AppColors.neutral500,
              size: 22,
            ),
          ),
      ],
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cameras',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: AppColors.neutral900),
              ),
              Text(
                'Live camera fleet, agents, events, and Qwen verification',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Detection callout with a pulsing red border-and-glow, so the box reads as
/// an active alert rather than a static label.
class _DetectionHighlight extends StatefulWidget {
  const _DetectionHighlight({required this.child});

  final Widget child;

  @override
  State<_DetectionHighlight> createState() => _DetectionHighlightState();
}

class _DetectionHighlightState extends State<_DetectionHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            width: 1.5,
            color: Color.lerp(
              Colors.white.withValues(alpha: 0.18),
              AppColors.danger,
              _t.value,
            )!,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.danger.withValues(alpha: 0.35 * _t.value),
              blurRadius: 20,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _Blink extends StatefulWidget {
  const _Blink({required this.child});

  final Widget child;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: 0.35,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

enum _RevealStyle { rise, slideLeft, slideRight, zoom }

/// One-shot entrance that plays when the child first scrolls into the lower
/// ~88% of the viewport (or immediately if it starts there).
class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.child,
    this.delay = Duration.zero,
    this.style = _RevealStyle.rise,
  });

  final Widget child;
  final Duration delay;
  final _RevealStyle style;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  ScrollPosition? _position;
  bool _revealed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_maybeReveal);
      _position = position;
      _position?.addListener(_maybeReveal);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeReveal());
  }

  @override
  void dispose() {
    _position?.removeListener(_maybeReveal);
    _controller.dispose();
    super.dispose();
  }

  void _maybeReveal() {
    if (!mounted || _revealed) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < MediaQuery.sizeOf(context).height * 0.88) {
      _revealed = true;
      _position?.removeListener(_maybeReveal);
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final remaining = 1 - _t.value;
        final content = switch (widget.style) {
          _RevealStyle.rise => Transform.translate(
            offset: Offset(0, 26 * remaining),
            child: child,
          ),
          _RevealStyle.slideLeft => Transform.translate(
            offset: Offset(-48 * remaining, 0),
            child: child,
          ),
          _RevealStyle.slideRight => Transform.translate(
            offset: Offset(48 * remaining, 0),
            child: child,
          ),
          _RevealStyle.zoom => Transform.scale(
            scale: 0.94 + 0.06 * _t.value,
            child: child,
          ),
        };
        return Opacity(opacity: _t.value, child: content);
      },
      child: widget.child,
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 520
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.sm * 2) / 3;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: const [
            _MiniMetric(
              icon: Icons.videocam_outlined,
              label: 'Online cameras',
              value: '3/3',
              tone: AppColors.success,
            ),
            _MiniMetric(
              icon: Icons.smart_toy_outlined,
              label: 'Armed agents',
              value: '6',
              tone: AppColors.success,
            ),
            _MiniMetric(
              icon: Icons.fact_check_outlined,
              label: 'Qwen verdicts',
              value: '12',
              tone: AppColors.info,
            ),
          ].map((child) => SizedBox(width: itemWidth, child: child)).toList(),
        );
      },
    );
  }
}

class _CameraPreviewCard extends StatelessWidget {
  const _CameraPreviewCard();

  @override
  Widget build(BuildContext context) {
    return _LightPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Front Door',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppColors.neutral900),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: AppRadius.lgAll,
                gradient: const LinearGradient(
                  colors: [Color(0xFF17202A), Color(0xFF243444)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/landing/frontdoor-cctv.gif',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0.25, -0.2),
                      gaplessPlayback: true,
                    ),
                  ),
                  const Positioned.fill(child: _CameraGridOverlay()),
                  Positioned(
                    left: 20,
                    top: 22,
                    child: _DarkPill(
                      icon: Icons.circle,
                      label: 'Live MJPEG stream',
                      color: AppColors.danger,
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: _DetectionHighlight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Person detected',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Qwen verification pending',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.neutral300),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: const [
              _ControlButton(
                icon: Icons.camera_alt_outlined,
                label: 'Snapshot',
              ),
              _ControlButton(icon: Icons.keyboard_arrow_left, label: 'Pan'),
              _ControlButton(icon: Icons.keyboard_arrow_up, label: 'Tilt'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentPreviewCard extends StatelessWidget {
  const _AgentPreviewCard();

  @override
  Widget build(BuildContext context) {
    return _LightPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(_agentIconAsset, width: 36, height: 36),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Protection agent',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: AppColors.neutral900),
                ),
              ),
              const _LightStatusPill(label: 'armed', tone: AppColors.success),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Alert when a person lingers near the front door after 10 PM.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          const _AgentChip(label: 'Front Door'),
          const SizedBox(height: AppSpacing.sm),
          const _AgentChip(label: 'Person detection'),
        ],
      ),
    );
  }
}

class _AuditPreviewCard extends StatelessWidget {
  const _AuditPreviewCard();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('snapshot', 'Fetched live frame'),
      ('pan', 'Adjusted camera angle'),
      ('verdict', 'Needs review'),
    ];
    return _LightPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Qwen audit trail',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: AppColors.neutral900),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    row.$1,
                    style: AppTypography.mono(
                      size: 11.5,
                      color: AppColors.neutral700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProofSection extends StatelessWidget {
  const _ProofSection({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ProofItem(
        icon: Icons.router_outlined,
        title: 'Real edge architecture',
        body:
            'ESP32 cameras stream through a laptop edge bridge that detects '
            'events close to the source, before anything reaches the cloud.',
      ),
      _ProofItem(
        icon: Icons.psychology_alt_outlined,
        title: 'Qwen Cloud verification',
        body:
            'Qualifying events are reviewed by Qwen Cloud, which reasons about '
            'the scene and confirms a real match before anyone is alerted.',
      ),
      _ProofItem(
        icon: Icons.monitor_heart_outlined,
        title: 'Operator console',
        body:
            'Flutter web shows camera health, live streams, PTZ controls, '
            'agent assignment, realtime events, clips, and push alerts.',
      ),
    ];
    return _DarkSection(
      child: _ResponsiveGrid(
        compact: compact,
        children: items.map((item) => _ProofCard(item: item)).toList(),
      ),
    );
  }
}

class _TraditionalVsAgenticSection extends StatelessWidget {
  const _TraditionalVsAgenticSection({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const items = [
      _ComparisonItem(
        icon: Icons.notifications_active_outlined,
        aspect: 'Alerting',
        traditional:
            'Motion and pixel triggers fire on shadows, pets, rain, and headlights — a flood of false alarms that trains operators to ignore them.',
        agentic:
            'Edge detectors flag candidates, then Qwen Cloud verifies the event against your rule before anyone is alerted.',
      ),
      _ComparisonItem(
        icon: Icons.inbox_outlined,
        aspect: 'What you review',
        traditional:
            'Operators scrub hours of continuous footage to find the one moment that actually mattered.',
        agentic:
            'Only verified events reach the timeline — each with a plain-English summary, snapshot, and clip.',
      ),
      _ComparisonItem(
        icon: Icons.rule_outlined,
        aspect: 'Rules',
        traditional:
            'Fixed motion zones and schedules that an installer has to reconfigure on-site.',
        agentic:
            'Natural-language rules like “alert if a person lingers at the front door after 10 PM,” editable in seconds.',
      ),
      _ComparisonItem(
        icon: Icons.psychology_outlined,
        aspect: 'Verdict & context',
        traditional:
            'A raw clip with no explanation of what happened or how urgent it is.',
        agentic:
            'A reasoned verdict with severity, a confidence score, and a recommended action: notify, monitor, or escalate.',
      ),
      _ComparisonItem(
        icon: Icons.travel_explore_outlined,
        aspect: 'Active investigation',
        traditional:
            'A passive recorder — it captures frames, it does not investigate them.',
        agentic:
            'The agent gathers more evidence: pulls a fresh snapshot, pans the camera, and checks device status and recent events.',
      ),
      _ComparisonItem(
        icon: Icons.verified_outlined,
        aspect: 'Response & audit',
        traditional:
            'You find out hours later when someone checks the DVR, and take the footage at face value.',
        agentic:
            'High-severity events push a realtime alert the moment they are verified, and every AI tool call is written to an auditable trail.',
      ),
    ];

    return _LightSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            eyebrow: 'Traditional vs. agentic',
            title: 'A camera that reasons, not just records.',
            body:
                'Traditional CCTV records everything and alerts on movement, leaving people to sort real threats from noise. Erlang AI Vision adds an AI agent that verifies, explains, and investigates every event before it interrupts you.',
          ),
          const SizedBox(height: AppSpacing.xxl),
          // A three-column table reads best on wide screens; on narrow screens
          // it cannot fit, so fall back to stacked per-dimension cards.
          if (compact)
            for (final item in items) _ComparisonRow(item: item)
          else
            _ComparisonTable(items: items),
        ],
      ),
    );
  }
}

class _ComparisonItem {
  const _ComparisonItem({
    required this.icon,
    required this.aspect,
    required this.traditional,
    required this.agentic,
  });

  final IconData icon;
  final String aspect;
  final String traditional;
  final String agentic;
}

/// Full comparison table for wide screens: a dimension column plus the two
/// approaches, with the agentic column tinted so it reads as the recommended
/// side.
class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.items});

  final List<_ComparisonItem> items;

  // Column flex weights: dimension, traditional, agentic.
  static const _colFlex = [1.0, 1.5, 1.5];

  @override
  Widget build(BuildContext context) {
    final total = _colFlex[0] + _colFlex[1] + _colFlex[2];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.lgAll,
        child: Stack(
          children: [
            // Continuous tint behind the agentic column, painted full height so
            // it stays unbroken regardless of per-row height differences.
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerRight,
                widthFactor: _colFlex[2] / total,
                child: const ColoredBox(color: AppColors.primaryContainer),
              ),
            ),
            Table(
              columnWidths: {
                0: FlexColumnWidth(_colFlex[0]),
                1: FlexColumnWidth(_colFlex[1]),
                2: FlexColumnWidth(_colFlex[2]),
              },
              border: const TableBorder(
                horizontalInside: BorderSide(color: AppColors.lightBorder),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                _headerRow(context),
                for (final item in items) _bodyRow(context, item),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _headerRow(BuildContext context) {
    return const TableRow(
      children: [
        _TableCellBox(child: SizedBox.shrink()),
        _TableCellBox(
          child: _ColumnHeader(
            icon: Icons.videocam_off_outlined,
            label: 'Traditional CCTV',
            color: AppColors.neutral500,
          ),
        ),
        _TableCellBox(
          child: _ColumnHeader(
            icon: Icons.verified_outlined,
            label: 'Erlang AI Vision',
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  TableRow _bodyRow(BuildContext context, _ComparisonItem item) {
    final textTheme = Theme.of(context).textTheme;
    return TableRow(
      children: [
        _TableCellBox(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, color: AppColors.primary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.aspect,
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.neutral900,
                  ),
                ),
              ),
            ],
          ),
        ),
        _TableCellBox(
          child: Text(
            item.traditional,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.neutral600),
          ),
        ),
        _TableCellBox(
          child: Text(
            item.agentic,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.neutral800),
          ),
        ),
      ],
    );
  }
}

/// A padded, transparent table cell. The agentic column's tint is painted
/// behind the whole table (see [_ComparisonTable]).
class _TableCellBox extends StatelessWidget {
  const _TableCellBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: child,
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Stacked per-dimension card, used on narrow screens where the table cannot
/// fit.
class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.item});

  final _ComparisonItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, color: AppColors.primary, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text(item.aspect, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _ComparisonCell(
            label: 'Traditional CCTV',
            text: item.traditional,
            icon: Icons.close_rounded,
            accent: AppColors.neutral500,
            background: AppColors.neutral100,
            textColor: AppColors.neutral600,
          ),
          const SizedBox(height: AppSpacing.sm),
          _ComparisonCell(
            label: 'Erlang AI Vision',
            text: item.agentic,
            icon: Icons.check_rounded,
            accent: AppColors.primary,
            background: AppColors.primaryContainer,
            textColor: AppColors.neutral800,
          ),
        ],
      ),
    );
  }
}

class _ComparisonCell extends StatelessWidget {
  const _ComparisonCell({
    required this.label,
    required this.text,
    required this.icon,
    required this.accent,
    required this.background,
    required this.textColor,
  });

  final String label;
  final String text;
  final IconData icon;
  final Color accent;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 14),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accent,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: textColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgenticInvestigationSection extends StatelessWidget {
  const _AgenticInvestigationSection({required this.compact, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final heading = const _SectionHeading(
      dark: true,
      eyebrow: 'How it works',
      title: 'The agent investigates before it interrupts you.',
      body:
          'When an edge detector flags a candidate, the event runs a three-stage pipeline. Qwen Cloud decides whether it truly matches your rule — gathering more evidence first when it helps — then returns an auditable verdict.',
    );

    const stages = [
      _StageItem(
        step: 'Stage 1',
        title: 'Edge detection',
        body:
            'ESP32 cameras and the laptop bridge run YOLO (and optional YAMNet audio) to flag candidate events on-site.',
      ),
      _StageItem(
        step: 'Stage 2',
        title: 'Local triage',
        body:
            'A local Qwen model filters obvious noise so only meaningful candidates reach the cloud.',
      ),
      _StageItem(
        step: 'Stage 3',
        title: 'Cloud verification',
        body:
            'Qwen Cloud reasons about the event against your natural-language rule and issues the final verdict.',
      ),
    ];

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stage in stages) _StageCard(item: stage),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Tools the agent can call',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _ToolChip(icon: Icons.camera_alt_outlined, label: 'Live snapshot'),
            _ToolChip(icon: Icons.control_camera_outlined, label: 'Pan camera'),
            _ToolChip(
              icon: Icons.monitor_heart_outlined,
              label: 'Device status',
            ),
            _ToolChip(
              icon: Icons.history_outlined,
              label: 'Recent events & clips',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Every tool call is logged to the event’s audit trail.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.neutral400),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _ImagePlaceholder(
          dark: true,
          label: 'Screenshot: event verdict & tool-call trail',
          aspectRatio: 16 / 10,
        ),
        SizedBox(height: AppSpacing.lg),
        _VerdictCard(),
      ],
    );

    return _DarkSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: AppSpacing.xxl),
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                const SizedBox(height: AppSpacing.xl),
                right,
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: AppSpacing.xxxl),
                Expanded(child: right),
              ],
            ),
        ],
      ),
    );
  }
}

class _StageItem {
  const _StageItem({
    required this.step,
    required this.title,
    required this.body,
  });

  final String step;
  final String title;
  final String body;
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.item});

  final _StageItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.step,
            style: AppTypography.tabular(
              Theme.of(context).textTheme.labelLarge!.copyWith(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.neutral300),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('verified', 'true'),
      ('severity', 'high'),
      ('confidence', '0.92'),
      ('recommended_action', 'notify'),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.neutral900,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                color: AppColors.accentOrange,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Qwen verdict',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      row.$1,
                      style: AppTypography.mono(
                        size: 12.5,
                        color: AppColors.neutral400,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: AppTypography.mono(
                        size: 12.5,
                        color: AppColors.accentOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'summary: Person lingering at the front door after hours.',
            style: AppTypography.mono(size: 12.5, color: AppColors.neutral300),
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({
    required this.label,
    this.aspectRatio = 16 / 9,
    this.dark = false,
  });

  final String label;
  final double aspectRatio;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final borderColor = dark
        ? Colors.white.withValues(alpha: 0.20)
        : AppColors.neutral300;
    final backgroundColor = dark
        ? Colors.white.withValues(alpha: 0.04)
        : AppColors.neutral100;
    final foreground = dark ? AppColors.neutral300 : AppColors.neutral500;
    return ClipRRect(
      borderRadius: AppRadius.lgAll,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    color: foreground,
                    size: 32,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: foreground),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Image placeholder',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground.withValues(alpha: 0.7),
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchitectureSection extends StatelessWidget {
  const _ArchitectureSection({required this.compact, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _LightSection(
      key: const ValueKey('architecture'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            eyebrow: 'Architecture',
            title: 'From camera frame to verified alert.',
            body:
                'Cameras stay on your local network. The edge bridge is the '
                'only thing that talks to the cloud, and Qwen verifies every '
                'event before it becomes an alert.',
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _Eyebrow(label: 'End-to-end flow'),
          const SizedBox(height: AppSpacing.md),
          _ArchitectureFlowImage(compact: compact),
          const SizedBox(height: AppSpacing.xl),
          const _Eyebrow(label: 'Cloud architecture'),
          const SizedBox(height: AppSpacing.md),
          _CloudArchitecturePlaceholder(compact: compact),
        ],
      ),
    );
  }
}

class _ArchitectureFlowImage extends StatelessWidget {
  const _ArchitectureFlowImage({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutral900,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.lightBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        _architectureFlowAsset,
        width: double.infinity,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Erlang AI Vision architecture flow',
        errorBuilder: (context, error, stackTrace) => Padding(
          padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
          child: _WorkflowDiagram(compact: compact),
        ),
      ),
    );
  }
}

class _UseCaseImpactSection extends StatelessWidget {
  const _UseCaseImpactSection({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visual = ClipRRect(
      borderRadius: AppRadius.lgAll,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.asset(
          _scenarioAsset,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: AppColors.neutral900,
            alignment: Alignment.center,
            child: const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );

    final impact = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _SectionHeading(
          dark: true,
          eyebrow: 'Use case impact',
          title: 'Security teams review moments, not hours of footage.',
          body:
              'The product is built for front doors, corridors, storage rooms, and small-site monitoring where cheap cameras need better context before a human is interrupted.',
        ),
        SizedBox(height: AppSpacing.xl),
        _CapabilityRow(
          icon: Icons.timer_outlined,
          title: 'Less manual review',
          body:
              'Operators spend their time on confirmed incidents instead of watching uneventful feeds.',
        ),
        _CapabilityRow(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy-aware edge filtering',
          body:
              'Local detection reduces unnecessary cloud calls and keeps routine frames close to the camera path.',
        ),
        _CapabilityRow(
          icon: Icons.crisis_alert_outlined,
          title: 'Faster response loops',
          body:
              'Operators can inspect, pan, tilt, and confirm events from the web console when something needs attention.',
        ),
      ],
    );

    return _DarkSection(
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                visual,
                const SizedBox(height: AppSpacing.xl),
                impact,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 6, child: visual),
                const SizedBox(width: AppSpacing.xxxl),
                Expanded(flex: 5, child: impact),
              ],
            ),
    );
  }
}

class _CloudArchitecturePlaceholder extends StatelessWidget {
  const _CloudArchitecturePlaceholder({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: compact ? 220 : 360),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: compact ? 36 : 48,
              color: AppColors.neutral400,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Cloud architecture image placeholder',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.neutral700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Replace this with the final architecture visual.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.neutral500),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectResourcesSection extends StatelessWidget {
  const _ProjectResourcesSection({required this.compact, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _LightSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const _Eyebrow(label: 'Resources'),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Explore the project.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.neutral900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          _ResponsiveGrid(
            compact: compact,
            children: const [
              _RepoCard(
                icon: Icons.hub_outlined,
                title: 'Erlang Fullstack',
                subtitle: 'Web console, FastAPI backend, cloud deployment.',
                url: _githubUrl,
                featured: true,
              ),
              _RepoCard(
                icon: Icons.camera_alt_outlined,
                title: 'Erlang IoT Firmware',
                subtitle: 'ESP32 camera firmware.',
                url: _iotRepoUrl,
              ),
              _RepoCard(
                icon: Icons.memory_outlined,
                title: 'Erlang Laptop Edge',
                subtitle: 'On-site detection and camera bridge.',
                url: _laptopEdgeRepoUrl,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepoCard extends StatelessWidget {
  const _RepoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
    this.featured = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 34),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.neutral900,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.neutral600),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (featured)
            FilledButton(
              onPressed: () => openExternalUrl(url),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: 14,
                ),
              ),
              child: const Text('View on GitHub'),
            )
          else
            TextButton(
              onPressed: () => openExternalUrl(url),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View on GitHub'),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BrushUnderline extends StatelessWidget {
  const _BrushUnderline({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // A tight line box (height 1.0) keeps the inline baseline flush with the
    // surrounding TextSpan; the paragraph's line height would otherwise shift
    // this word a few pixels off the shared baseline.
    return CustomPaint(
      painter: _BrushStrokePainter(color: AppColors.primary),
      child: Text(text, style: style?.copyWith(height: 1.0)),
    );
  }
}

/// Hand-drawn-looking underline: two slightly offset bezier passes read as a
/// single freestyle marker stroke under the word.
class _BrushStrokePainter extends CustomPainter {
  const _BrushStrokePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (h * 0.045).clamp(2.0, 6.0);
    final y = h * 0.99;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(w * 0.01, y)
      ..quadraticBezierTo(w * 0.3, y + h * 0.035, w * 0.58, y - h * 0.002)
      ..quadraticBezierTo(w * 0.82, y - h * 0.03, w * 0.99, y - h * 0.01);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BrushStrokePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FooterCta extends StatelessWidget {
  const _FooterCta({required this.onLaunchDemo, required this.onLogin});

  final VoidCallback onLaunchDemo;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF080B10), Color(0xFF10161E), Color(0xFF170E0B)],
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 96,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Text(
                'See it in action.',
                textAlign: TextAlign.center,
                style: AppTypography.display(40, height: 1.1),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Launch the demo console, or sign in to your own cameras.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.neutral300),
              ),
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  FilledButton.icon(
                    onPressed: onLaunchDemo,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Demo Video'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: 16,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.login_outlined, size: 18),
                    label: const Text('Login'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkflowDiagram extends StatelessWidget {
  const _WorkflowDiagram({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('ESP32 camera', Icons.camera_alt_outlined),
      ('Laptop edge bridge', Icons.memory_outlined),
      ('FastAPI backend', Icons.hub_outlined),
      ('Qwen verifier', Icons.psychology_outlined),
      ('Flutter console', Icons.dashboard_outlined),
    ];
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i += 1) {
      children.add(
        Expanded(
          child: _WorkflowStep(label: steps[i].$1, icon: steps[i].$2),
        ),
      );
      if (i != steps.length - 1) {
        children.add(
          Icon(
            compact ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
            color: AppColors.primary,
          ),
        );
      }
    }
    return compact
        ? Column(
            children: children
                .map(
                  (child) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: child is Expanded ? child.child : child,
                  ),
                )
                .toList(),
          )
        : Row(children: children);
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

class _DarkSection extends StatelessWidget {
  const _DarkSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.darkBackground,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.contentMaxWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LightSection extends StatelessWidget {
  const _LightSection({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.neutral50,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.contentMaxWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.compact, required this.children});

  final bool compact;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .map(
              (child) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: child,
              ),
            )
            .toList(),
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i += 1) ...[
            Expanded(child: children[i]),
            if (i != children.length - 1) const SizedBox(width: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.body,
    this.dark = false,
  });

  final String eyebrow;
  final String title;
  final String body;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Eyebrow(label: eyebrow),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: dark ? Colors.white : AppColors.neutral900,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: dark ? AppColors.neutral300 : AppColors.neutral600,
          ),
        ),
      ],
    );
  }
}

class _ProofCard extends StatelessWidget {
  const _ProofCard({required this.item});

  final _ProofItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: AppColors.accentOrange, size: 28),
          const SizedBox(height: AppSpacing.lg),
          Text(
            item.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            item.body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.neutral300),
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accentOrange),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.neutral300),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofItem {
  const _ProofItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return _LightPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.neutral900,
                  ),
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LightPanel extends StatelessWidget {
  const _LightPanel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: child,
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      height: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: AppRadius.mdAll,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.neutral700, size: 16),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentChip extends StatelessWidget {
  const _AgentChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.onPrimaryContainer),
      ),
    );
  }
}

class _LightStatusPill extends StatelessWidget {
  const _LightStatusPill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone),
      ),
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        children: [
          _Blink(child: Icon(icon, color: color, size: 10)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppColors.accentOrange,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _CameraGridOverlay extends StatelessWidget {
  const _CameraGridOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _LandingGrid extends StatelessWidget {
  const _LandingGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BackgroundGridPainter());
  }
}

class _SignalGlow extends StatefulWidget {
  const _SignalGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_SignalGlow> createState() => _SignalGlowState();
}

class _SignalGlowState extends State<_SignalGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) => Transform.scale(
        scale: 1 + 0.08 * _t.value,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                widget.color.withValues(alpha: 0.14 + 0.08 * _t.value),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BackgroundGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
