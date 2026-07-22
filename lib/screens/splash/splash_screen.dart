import 'package:flutter/material.dart';
import '../../services/firebase_push_service.dart';
import '../../services/offline_status_service.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../auth/role_select_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../kind/kind_shell.dart';
import '../student/student_shell.dart';
import '../teacher/teacher_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<double> _slide;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    OfflineStatusService.instance.setShowBanner(false);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
    );
    _scale = Tween(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.8, curve: Curves.elasticOut),
      ),
    );
    _slide = Tween(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.2, 0.9, curve: Curves.easeOut),
      ),
    );

    // Animate for polish, but never block navigation on the ticker or network.
    _ctrl.forward();
    _leaveSplash();
  }

  Future<void> _leaveSplash() async {
    // Short brand moment; never wait on animation tickers or network.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted || _navigated) return;

    try {
      await _navigateNext().timeout(const Duration(seconds: 4));
    } catch (_) {
      if (!mounted || _navigated) return;
      _go(const RoleSelectScreen());
    }
  }

  Future<void> _navigateNext() async {
    final api = ApiService();

    final hasSession = await api.hasValidSession();
    if (!mounted || _navigated) return;

    if (!hasSession) {
      final seenOnboarding = await api.hasSeenOnboarding();
      if (!mounted || _navigated) return;
      _go(seenOnboarding ? const RoleSelectScreen() : const OnboardingScreen());
      return;
    }

    // Local role only — never wait on /me while offline (that left users stuck).
    final role = ((await api.getRole()) ?? 'student').toLowerCase().trim();
    if (!mounted || _navigated) return;

    Widget dest;
    if (role == 'teacher') {
      dest = const TeacherShell();
    } else if (role == 'kind') {
      dest = const KindShell();
    } else {
      // Do not auto-open League on cold start (blocks offline / face-check).
      dest = const StudentShell(openSilOnStart: false);
    }

    _go(dest);

    if (role == 'student' || role.isEmpty) {
      // ignore: unawaited_futures
      api.ensureStudentProfile();
    }
    // ignore: unawaited_futures
    FirebasePushService.instance.registerAfterLogin().catchError((_) {});
  }

  void _go(Widget dest) {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => dest,
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.splash),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Center(
              child: FadeTransition(
                opacity: _fade,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF7C3AED).withOpacity(0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: Color(0xFF7C3AED),
                            size: 44,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Scholaxia',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Learn smarter with Sia',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
