import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Homepage promotional carousel.
///
/// Slides are photo-led, branded and keyboard/pointer operable (prev/next
/// buttons plus tappable indicators). Auto-rotation is gentle and can be
/// switched off wholesale via [autoAdvance] — widget tests set it to false so
/// a periodic timer can never keep `pumpAndSettle` spinning.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({super.key, required this.banners, this.height});

  final List<PromoBanner> banners;
  final double? height;

  /// Auto-advance is on by default; tests disable it.
  static bool autoAdvance = true;

  /// Delay between automatic slide changes.
  static const Duration autoAdvanceInterval = Duration(seconds: 6);

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _hovering = false;
  bool _userPaused = false;

  @override
  void initState() {
    super.initState();
    _maybeSchedule();
  }

  @override
  void didUpdateWidget(covariant PromoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length) {
      _index = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
      _restart();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _canAutoAdvance =>
      PromoCarousel.autoAdvance && widget.banners.length > 1;

  void _maybeSchedule() => _restart();

  void _restart() {
    _timer?.cancel();
    if (!_canAutoAdvance || _userPaused || _hovering) return;
    _timer = Timer.periodic(PromoCarousel.autoAdvanceInterval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _setPaused(bool paused) {
    setState(() => _userPaused = paused);
    _restart();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.banners.length) return;
    _controller.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  double _resolveHeight(BuildContext context) {
    if (widget.height != null) return widget.height!;
    final width = MediaQuery.sizeOf(context).width;
    if (AppBreakpoints.isDesktop(width)) return 320;
    if (AppBreakpoints.isTablet(width)) return 280;
    return 220;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();
    final height = _resolveHeight(context);
    final showControls = widget.banners.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) {
            _hovering = true;
            _restart();
          },
          onExit: (_) {
            _hovering = false;
            _restart();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: widget.banners.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _Slide(
                      banner: widget.banners[i],
                      onTap: () => _open(widget.banners[i]),
                    ),
                  ),
                  if (showControls)
                    Positioned(
                      left: AppSpacing.md,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ArrowButton(
                          icon: Icons.chevron_left_rounded,
                          tooltip: 'Previous promotion',
                          onTap: () => _goTo(_index - 1),
                        ),
                      ),
                    ),
                  if (showControls)
                    Positioned(
                      right: AppSpacing.md,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ArrowButton(
                          icon: Icons.chevron_right_rounded,
                          tooltip: 'Next promotion',
                          onTap: () => _goTo(_index + 1),
                        ),
                      ),
                    ),
                  if (showControls)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: AppSpacing.md,
                      child: _Indicators(
                        count: widget.banners.length,
                        index: _index,
                        onTap: _goTo,
                      ),
                    ),
                  if (showControls)
                    Positioned(
                      right: AppSpacing.xl,
                      bottom: AppSpacing.md,
                      child: _PauseToggle(
                        paused: _userPaused,
                        onTap: () => _setPaused(!_userPaused),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (widget.banners.any((b) => b.isDemo)) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Demo promotions for development — they link to real pages '
                  'and apply no discount at checkout.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _open(PromoBanner banner) {
    final target = banner.target.trim();
    if (target.isEmpty) return;
    context.go(target);
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.banner, required this.onTap});

  final PromoBanner banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _hex(banner.accent) ?? AppColors.forestDeep;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = AppBreakpoints.isDesktop(width);
    return Stack(
      fit: StackFit.expand,
      children: [
        AppImage(
          url: banner.imageUrl,
          fallbackIcon: Icons.local_dining_rounded,
          fallbackColor: accent,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isDesktop ? Alignment.centerLeft : Alignment.topCenter,
              end: isDesktop ? Alignment.centerRight : Alignment.bottomCenter,
              colors: [
                accent.withValues(alpha: 0.94),
                accent.withValues(alpha: isDesktop ? 0.62 : 0.80),
                Colors.black.withValues(alpha: 0.32),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(isDesktop ? AppSpacing.xxl : AppSpacing.xl),
          child: Align(
            alignment: isDesktop ? Alignment.centerLeft : Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop ? 520 : 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((banner.badge ?? '').isNotEmpty)
                    Pill(
                      label: banner.badge!,
                      icon: Icons.local_offer_outlined,
                      color: AppColors.forestDeep,
                      background: AppColors.lime,
                      dense: true,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: isDesktop ? 34 : 24,
                          height: 1.1,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    banner.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onForestMuted,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                  if (banner.ctaLabel.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.lime,
                        foregroundColor: AppColors.forestDeep,
                        minimumSize: const Size(0, 46),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(banner.ctaLabel),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.34),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

class _Indicators extends StatelessWidget {
  const _Indicators(
      {required this.count, required this.index, required this.onTap});

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            label: 'Promotion ${i + 1} of $count',
            selected: i == index,
            button: true,
            child: GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == index ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == index
                      ? AppColors.lime
                      : Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PauseToggle extends StatelessWidget {
  const _PauseToggle({required this.paused, required this.onTap});

  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.34),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: paused ? 'Resume auto-rotation' : 'Pause auto-rotation',
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

Color? _hex(String? value) {
  if (value == null) return null;
  var v = value.trim().replaceFirst('#', '');
  if (v.length == 6) v = 'FF$v';
  if (v.length != 8) return null;
  final parsed = int.tryParse(v, radix: 16);
  return parsed == null ? null : Color(parsed);
}
