import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'home/home_screen.dart';
import 'sia/sia_screen.dart';
import 'cbt/cbt_screen.dart';
import 'community/community_screen.dart';
import 'profile/profile_screen.dart';

class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SiaScreen(),
    CbtScreen(),
    CommunityScreen(),
    ProfileScreen(),
  ];

  static const _navItems = [
    _NavItem(icon: Icons.home_outlined, label: 'Home'),
    _NavItem(icon: Icons.smart_toy_outlined, label: 'Sia'),
    _NavItem(icon: Icons.quiz_outlined, label: 'CBT'),
    _NavItem(icon: Icons.people_outline, label: 'Community'),
    _NavItem(icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        height: 68,
        decoration: BoxDecoration(
          color: context.headerColor,
          border: Border(top: BorderSide(color: context.borderColor)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(context.isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_navItems.length, (i) {
            final active = i == _currentIndex;
            final activeColor = context.accentColor;
            final inactiveColor = context.greyLColor;
            return GestureDetector(
              onTap: () => setState(() => _currentIndex = i),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 60,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: active
                            ? activeColor.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_navItems[i].icon,
                          color: active ? activeColor : inactiveColor,
                          size: 22),
                    ),
                    const SizedBox(height: 2),
                    Text(_navItems[i].label,
                        style: TextStyle(
                          color: active ? activeColor : inactiveColor,
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                        )),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
