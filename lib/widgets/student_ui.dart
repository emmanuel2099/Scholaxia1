import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Section title with optional action link.
class StudentSectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const StudentSectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: AppGradients.primaryButton,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: context.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  action!,
                  style: TextStyle(
                    color: context.accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mini stat card for streaks, scores, etc.
class StudentStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final List<Color> gradient;

  const StudentStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 110,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.9), size: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One slide for the home promo carousel.
class StudentBannerSlide {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback? onTap;
  final String? badge;
  final List<Color>? colors;

  const StudentBannerSlide({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.icon,
    this.onTap,
    this.badge,
    this.colors,
  });
}

/// Horizontal swipe banner slider (one card at a time + dots).
class StudentBannerSlider extends StatefulWidget {
  final List<StudentBannerSlide> slides;
  final double height;

  const StudentBannerSlider({
    super.key,
    required this.slides,
    this.height = 140,
  });

  @override
  State<StudentBannerSlider> createState() => _StudentBannerSliderState();
}

class _StudentBannerSliderState extends State<StudentBannerSlider> {
  late final PageController _controller;
  int _index = 0;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (widget.slides.length > 1) {
      _auto = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted || !_controller.hasClients) return;
        final next = (_index + 1) % widget.slides.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final s = widget.slides[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _BannerCard(slide: s),
              );
            },
          ),
        ),
        if (widget.slides.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.slides.length, (i) {
              final on = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: on ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: on
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF7C3AED).withOpacity(0.28),
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  final StudentBannerSlide slide;
  const _BannerCard({required this.slide});

  @override
  Widget build(BuildContext context) {
    final colors = slide.colors ??
        const [Color(0xFF5B21B6), Color(0xFF7C3AED), Color(0xFFA855F7)];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: slide.onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: colors[1].withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (slide.badge != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                slide.badge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            slide.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            slide.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.88),
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  slide.buttonLabel,
                                  style: TextStyle(
                                    color: slide.onTap == null
                                        ? const Color(0xFF7C3AED)
                                            .withOpacity(0.7)
                                        : const Color(0xFF7C3AED),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                                if (slide.onTap != null) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_forward_rounded,
                                      color: Color(0xFF7C3AED), size: 14),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: Icon(slide.icon, color: Colors.white, size: 24),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large featured CTA banner.
class StudentFeatureBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback onTap;

  const StudentFeatureBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StudentBannerSlider(
      slides: [
        StudentBannerSlide(
          title: title,
          subtitle: subtitle,
          buttonLabel: buttonLabel,
          icon: icon,
          onTap: onTap,
          badge: '✨ AI POWERED',
        ),
      ],
    );
  }
}

/// Back button shown when this screen was pushed on top of another (e.g. Quick Access).
class StudentBackButton extends StatelessWidget {
  final bool lightOnGradient;

  const StudentBackButton({super.key, this.lightOnGradient = false});

  @override
  Widget build(BuildContext context) {
    if (!Navigator.canPop(context)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: lightOnGradient
                  ? Colors.white.withOpacity(0.2)
                  : context.accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: lightOnGradient
                  ? Border.all(color: Colors.white.withOpacity(0.3))
                  : null,
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: lightOnGradient ? Colors.white : context.accentColor,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick-access tile with gradient icon area and tap color feedback.
class StudentQuickTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  const StudentQuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<StudentQuickTile> createState() => _StudentQuickTileState();
}

class _StudentQuickTileState extends State<StudentQuickTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.gradient.first;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _pressed
              ? Color.alphaBlend(accent.withOpacity(0.22), context.cardColor)
              : context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _pressed ? accent : context.borderColor,
            width: _pressed ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _pressed
                  ? accent.withOpacity(0.35)
                  : accent.withOpacity(context.isDark ? 0.08 : 0.12),
              blurRadius: _pressed ? 16 : 8,
              offset: Offset(0, _pressed ? 6 : 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _pressed
                        ? [accent, widget.gradient.last]
                        : widget.gradient,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(_pressed ? 0.5 : 0.35),
                      blurRadius: _pressed ? 12 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 22),
              ),
              const Spacer(),
              Text(
                widget.label,
                style: TextStyle(
                  color: _pressed ? accent : context.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: TextStyle(
                  color: context.greyColor,
                  fontSize: 11,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
