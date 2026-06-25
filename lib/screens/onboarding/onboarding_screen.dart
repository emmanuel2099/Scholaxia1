import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../auth/role_select_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OPage(
      image: 'asset/images/image copy 2.png',
      title: 'Personalized\nAI Tutoring',
      subtitle:
          'Get tailored study plans and 24/7 AI assistance to help you ace your JAMB, WAEC, and NECO exams.',
      isLast: false,
      skipLabel: 'Skip for now',
    ),
    _OPage(
      image: 'asset/images/image copy 3.png',
      title: 'Practice Smart with\nTimed CBT',
      subtitle:
          'Master the pressure of real exams with our simulated Computer Based Tests.',
      isLast: false,
      skipLabel: 'Skip to Dashboard',
    ),
    _OPage(
      image: 'asset/images/image.png',
      title: 'Join Live Classes\n& Community',
      subtitle:
          'Learn together with thousands of students. Get instant help from expert tutors and your peers in real-time.',
      isLast: true,
      skipLabel: 'By continuing, you agree to our Terms of Service',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _goToLogin();
    }
  }

  void _goToLogin() {
    ApiService().markOnboardingSeen();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const RoleSelectScreen()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _PageContent(page: _pages[i]),
            ),
          ),
          // Dots
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 28 : 8,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? context.accentColor
                        : context.borderColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor:
                          context.isDark ? AppColors.background : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(
                      _pages[_page].isLast ? 'Get Started' : 'Next',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pages[_page].isLast ? null : _goToLogin,
                  child: Text(
                    _pages[_page].skipLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _pages[_page].isLast
                          ? context.greyLColor
                          : context.greyColor,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OPage {
  final String image, title, subtitle, skipLabel;
  final bool isLast;
  const _OPage({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.isLast,
    required this.skipLabel,
  });
}

class _PageContent extends StatelessWidget {
  final _OPage page;
  const _PageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final imageHeight = (h * 0.52).clamp(140.0, h * 0.58);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.transparent],
                  stops: [0.65, 1.0],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: Image.asset(
                  page.image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: context.surfColor,
                    child: Center(
                      child: Icon(Icons.image_outlined,
                          size: 60, color: context.greyLColor),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.title,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: context.textColor,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      page.subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.greyColor,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
