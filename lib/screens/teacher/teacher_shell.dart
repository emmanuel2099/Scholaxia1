import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'ai/teacher_ai_screen.dart';
import 'cbt/teacher_cbt_screen.dart';
import 'classes/teacher_classes_screen.dart';
import 'dashboard/teacher_dashboard_screen.dart';
import 'grading/teacher_grading_screen.dart';
import 'notices/teacher_notices_screen.dart';
import 'profile/teacher_profile_screen.dart';

class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    TeacherDashboardScreen(),
    TeacherClassesScreen(),
    TeacherNoticesScreen(),
    TeacherGradingScreen(),
    TeacherCbtScreen(),
    TeacherAiScreen(),
    TeacherProfileScreen(embeddedInShell: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final accent = context.accentColor;
    final muted = context.greyColor;
    final items = [
      _NavItem(icon: Icons.grid_view_rounded, label: 'Dashboard'),
      _NavItem(icon: Icons.school_outlined, label: 'Classes'),
      _NavItem(icon: Icons.campaign_outlined, label: 'Notices'),
      _NavItem(icon: Icons.grading_outlined, label: 'Grading'),
      _NavItem(icon: Icons.quiz_outlined, label: 'CBT'),
      _NavItem(icon: Icons.smart_toy_outlined, label: 'AI'),
      _NavItem(icon: Icons.person_outline, label: 'Profile'),
    ];

    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: context.headerColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final isActive = i == _currentIndex;
          return GestureDetector(
            onTap: () => setState(() => _currentIndex = i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isActive
                          ? accent.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(items[i].icon,
                        color: isActive ? accent : muted,
                        size: 20),
                  ),
                  const SizedBox(height: 2),
                  Text(items[i].label,
                      style: TextStyle(
                          color: isActive ? accent : muted,
                          fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
