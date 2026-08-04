import 'package:flutter/material.dart';

import '../../services/app_prefs.dart';
import 'vendor_login_screen.dart';
import 'vendor_theme.dart';

class VendorOnboardingScreen extends StatefulWidget {
  const VendorOnboardingScreen({super.key});

  @override
  State<VendorOnboardingScreen> createState() => _VendorOnboardingScreenState();
}

class _VendorOnboardingScreenState extends State<VendorOnboardingScreen> {
  int _page = 0;
  final _controller = PageController();

  static const _pages = [
    (
      'Approve Orders With Ease',
      'Review student requests in one place and approve or reject with a single tap.',
    ),
    (
      'Seamless Door-to-Door Selling',
      'Students order from your store — you fulfill, update status, and keep sales moving.',
    ),
    (
      'Grow Your Market Store',
      'List books and products for Scholaxia students nationwide and track every sale.',
    ),
  ];

  static const _heroAsset = 'asset/images/vendor_onboarding_hero.png';

  Future<void> _finish() async {
    final prefs = await AppPrefs.instance();
    await prefs.setBool('vendor_onboarding_seen', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const VendorLoginScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed hero photo (same composition as the reference).
          Image.asset(
            _heroAsset,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF3A2A45), VendorTheme.maroonDark],
                ),
              ),
            ),
          ),
          // Soft top vignette + strong bottom scrim for white text.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x00000000),
                  Color(0x99000000),
                  Color(0xE6000000),
                ],
                stops: [0, 0.35, 0.62, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: _finish,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) {
                      final page = _pages[i];
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                page.$1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                page.$2,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 15,
                                  height: 1.45,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _pages.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _page ? 28 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_page == _pages.length - 1) {
                              _finish();
                              return;
                            }
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeInOut,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: VendorTheme.maroon,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(
                            _page == _pages.length - 1 ? 'Get Started' : 'Next',
                          ),
                        ),
                      ),
                    ],
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
