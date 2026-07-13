import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'ai/teacher_ai_screen.dart';
import 'classes/teacher_classes_screen.dart';
import 'dashboard/teacher_dashboard_screen.dart';
import 'grading/teacher_grading_screen.dart';
import 'groups/teacher_groups_screen.dart';
import 'notices/teacher_notices_screen.dart';
import 'profile/teacher_profile_screen.dart';

class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _currentIndex = 0;
  int _hostClassNonce = 0;

  void _goToTab(int i) => setState(() => _currentIndex = i);

  void _hostClass() {
    setState(() {
      _currentIndex = 1;
      _hostClassNonce++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        final screens = [
          TeacherDashboardScreen(
            onNavigate: _goToTab,
            onHostClass: _hostClass,
          ),
          TeacherClassesScreen(hostClassNonce: _hostClassNonce),
          const TeacherGroupsScreen(),
          const TeacherNoticesScreen(),
          const TeacherGradingScreen(),
          const TeacherAiScreen(),
          const TeacherProfileScreen(embeddedInShell: true),
        ];

        const navItems = [
          _NavItem(
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard_rounded,
            label: 'Home',
          ),
          _NavItem(
            icon: Icons.school_outlined,
            activeIcon: Icons.school_rounded,
            label: 'Classes',
          ),
          _NavItem(
            icon: Icons.groups_outlined,
            activeIcon: Icons.groups_rounded,
            label: 'Groups',
          ),
          _NavItem(
            icon: Icons.people_outline_rounded,
            activeIcon: Icons.people_rounded,
            label: 'Community',
          ),
          _NavItem(
            icon: Icons.grading_outlined,
            activeIcon: Icons.grading_rounded,
            label: 'Grading',
          ),
          _NavItem(
            icon: Icons.auto_awesome_outlined,
            activeIcon: Icons.auto_awesome_rounded,
            label: 'AI',
          ),
          _NavItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: 'Me',
          ),
        ];

        return Scaffold(
          backgroundColor: context.bgColor,
          extendBody: true,
          body: IndexedStack(index: _currentIndex, children: screens),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: context.isDark
                    ? const Color(0xFF1A1428).withOpacity(0.95)
                    : Colors.white.withOpacity(0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: context.isDark
                      ? const Color(0xFF2D2640)
                      : const Color(0xFFE9E5F5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(navItems.length, (i) {
                  final active = _currentIndex == i;
                  final item = navItems[i];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _currentIndex = i),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: active
                              ? context.accentColor.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              active ? item.activeIcon : item.icon,
                              color: active
                                  ? context.accentColor
                                  : context.greyColor,
                              size: active ? 21 : 19,
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                item.label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: active
                                      ? context.accentColor
                                      : context.greyColor,
                                  fontSize: 8.5,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
