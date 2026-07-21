import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../kind/kind_shared.dart';
import 'league_auth_screen.dart';
import 'login_screen.dart';

enum AccountRole { student, teacher, kind, gameChallenge }

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  void _openLogin(BuildContext context, AccountRole role) {
    if (role == AccountRole.gameChallenge) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LeagueAuthScreen()),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen(accountRole: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                decoration: BoxDecoration(
                  gradient: AppGradients.hero(context),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Who is signing in?',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose your account type to continue.',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.88),
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    _RoleCard(
                      icon: Icons.school_outlined,
                      title: 'Student',
                      subtitle:
                          'JAMB, WAEC, NECO prep, live classes, and CBT practice.',
                      color: context.accentColor,
                      onTap: () => _openLogin(context, AccountRole.student),
                    ),
                    const SizedBox(height: 12),
                    _RoleCard(
                      icon: Icons.emoji_events_outlined,
                      title: 'Game Challenge',
                      subtitle:
                          'Intellect League login — compete, earn coins, climb ranks.',
                      color: const Color(0xFF7C3AED),
                      onTap: () =>
                          _openLogin(context, AccountRole.gameChallenge),
                    ),
                    const SizedBox(height: 12),
                    _RoleCard(
                      icon: Icons.person_outline,
                      title: 'Teacher',
                      subtitle:
                          'Host live classes, grade work, and use Teacher AI.',
                      color: const Color(0xFF9333EA),
                      onTap: () => _openLogin(context, AccountRole.teacher),
                    ),
                    const SizedBox(height: 12),
                    _RoleCard(
                      icon: Icons.child_care_outlined,
                      title: 'Kid',
                      subtitle:
                          'Young learners (ages 3–12) with kid-safe AI tutoring.',
                      color: KidColors.accent,
                      onTap: () => _openLogin(context, AccountRole.kind),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Use the email and password for the account type you selected.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: context.greyLColor),
                    ),
                    const SizedBox(height: 24),
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

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cardColor,
      elevation: context.isDark ? 0 : 2,
      shadowColor: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color.withOpacity(0.2), color.withOpacity(0.08)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.textColor)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.greyColor,
                            height: 1.35)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
