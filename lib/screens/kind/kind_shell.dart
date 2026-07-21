import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../student/saved/saved_classes_screen.dart';
import 'kind_home_screen.dart';
import 'kind_live_screen.dart';
import 'kind_profile_screen.dart';
import 'kind_sia_screen.dart';

/// Kid learner app — polished UI matching the student experience.
class KindShell extends StatefulWidget {
  const KindShell({super.key});

  @override
  State<KindShell> createState() => _KindShellState();
}

class _KindShellState extends State<KindShell> {
  int _index = 0;
  final _savedKey = GlobalKey<SavedClassesScreenState>();

  void _goToTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        final screens = [
          KindHomeScreen(onNavigate: _goToTab),
          const KindSiaScreen(),
          const KindLiveScreen(),
          SavedClassesScreen(key: _savedKey),
          const KindProfileScreen(),
        ];

        const navItems = [
          _NavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Home',
          ),
          _NavItem(
            icon: Icons.auto_awesome_outlined,
            activeIcon: Icons.auto_awesome_rounded,
            label: 'Sia',
          ),
          _NavItem(
            icon: Icons.videocam_outlined,
            activeIcon: Icons.videocam_rounded,
            label: 'Live',
          ),
          _NavItem(
            icon: Icons.video_library_outlined,
            activeIcon: Icons.video_library_rounded,
            label: 'Saved',
          ),
          _NavItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: 'Profile',
          ),
        ];

        return Scaffold(
          backgroundColor: context.bgColor,
          extendBody: true,
          body: IndexedStack(index: _index, children: screens),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
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
                  BoxShadow(
                    color: Colors.black.withOpacity(
                      context.isDark ? 0.3 : 0.06,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(navItems.length, (i) {
                  final active = _index == i;
                  final item = navItems[i];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _index = i);
                        if (i == 3) _savedKey.currentState?.reload();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? context.accentColor.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              active ? item.activeIcon : item.icon,
                              color: active
                                  ? context.accentColor
                                  : context.greyColor,
                              size: active ? 22 : 20,
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                item.label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: active
                                      ? context.accentColor
                                      : context.greyColor,
                                  fontSize: 9.5,
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
