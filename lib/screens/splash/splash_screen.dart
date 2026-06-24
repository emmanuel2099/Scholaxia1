import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../auth/exam_subject_setup_screen.dart';
import '../auth/role_select_screen.dart';
import '../onboarding/onboarding_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _fade  = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.easeIn));
    _scale = Tween(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.8, curve: Curves.elasticOut)));
    _slide = Tween(begin: 30.0, end: 0.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.2, 0.9, curve: Curves.easeOut)));

    _ctrl.forward().then((_) async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final api = ApiService();

      if (await api.hasValidSession()) {
        final role = await api.resolveSessionRole();
        if (!mounted) return;

        if (role == null) {
          await api.clearTokens();
          if (!mounted) return;
          final seenOnboarding = await api.hasSeenOnboarding();
          Navigator.of(context).pushReplacement(PageRouteBuilder(
            pageBuilder: (_, __, ___) =>
                seenOnboarding ? const RoleSelectScreen() : const OnboardingScreen(),
            transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
            transitionDuration: const Duration(milliseconds: 500),
          ));
          return;
        }

        Widget dest;
        if (role == 'teacher') {
          dest = const TeacherShell();
        } else if (role == 'kind') {
          dest = const StudentShell();
        } else {
          final complete = await api.isSetupComplete();
          dest = complete ? const StudentShell() : const ExamSubjectSetupScreen();
        }

        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, __, ___) => dest,
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
          transitionDuration: const Duration(milliseconds: 500),
        ));

        if (role != 'teacher') {
          api.ensureStudentProfile();
        }
      } else {
        final seenOnboarding = await api.hasSeenOnboarding();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              seenOnboarding ? const RoleSelectScreen() : const OnboardingScreen(),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
          transitionDuration: const Duration(milliseconds: 500),
        ));
      }
    });
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB8F0CF), Color(0xFFF0FBF4), Colors.white],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
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
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.school_rounded,
                              color: Colors.white, size: 42),
                        ),
                        const SizedBox(height: 20),
                        const Text('Scholaxia',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                                letterSpacing: 0.5)),
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
