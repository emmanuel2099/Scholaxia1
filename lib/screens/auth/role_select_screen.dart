import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'login_screen.dart';

enum AccountRole { student, teacher, kind }

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  void _openLogin(BuildContext context, AccountRole role) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen(accountRole: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              const Text(
                'Who is signing in?',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose your account type to continue to login.',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.4),
              ),
              const SizedBox(height: 28),
              _RoleCard(
                icon: Icons.school_outlined,
                title: 'Student',
                subtitle: 'JAMB, WAEC, NECO prep, live classes, and CBT practice.',
                color: AppColorsLight.yellow,
                onTap: () => _openLogin(context, AccountRole.student),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.person_outline,
                title: 'Teacher',
                subtitle: 'Host live classes, grade work, post notices, and use Teacher AI.',
                color: const Color(0xFF22C55E),
                onTap: () => _openLogin(context, AccountRole.teacher),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.child_care_outlined,
                title: 'Kid',
                subtitle: 'Young learners (ages 3–12) with kid-safe AI tutoring.',
                color: const Color(0xFF6C63FF),
                onTap: () => _openLogin(context, AccountRole.kind),
              ),
              const Spacer(),
              const Center(
                child: Text(
                  'Use the email and password for the account type you selected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ),
              const SizedBox(height: 24),
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
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                            height: 1.35)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
