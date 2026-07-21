import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../services/access_code_service.dart';
import '../../services/community_badge.dart';
import '../../services/live_class_ring_service.dart';
import '../../services/local_notification_service.dart';
import '../../theme/app_theme.dart';
import '../kind/kind_shell.dart';
import 'home/home_screen.dart';
import 'sia/sia_screen.dart';
import 'cbt/cbt_screen.dart';
import 'community/community_screen.dart';
import 'profile/profile_screen.dart';
import 'sil/sil_entry.dart';

class StudentShell extends StatefulWidget {
  /// When true (Game Challenge / League login), open Intellect League after shell loads.
  final bool openSilOnStart;

  const StudentShell({super.key, this.openSilOnStart = false});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final _api = ApiService();
  Timer? _pollTimer;

  final List<Widget> _screens = [
    const HomeScreen(),
    const SiaScreen(),
    const CbtScreen(),
    const CommunityScreen(),
    const ProfileScreen(),
  ];

  static const _navItems = [
    _NavItem(
      icon: Icons.home_rounded,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome_rounded,
      label: 'Sia',
    ),
    _NavItem(
      icon: Icons.quiz_outlined,
      activeIcon: Icons.quiz_rounded,
      label: 'CBT',
    ),
    _NavItem(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: 'Community',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureStudentRole();
    _startPolling();
    LocalNotificationService.instance.init().then((_) {
      LocalNotificationService.instance.seedKnownNotifications(_api);
    });
    if (widget.openSilOnStart) {
      ApiService().setAppResumeMode('league');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SilEntryScreen()),
        );
      });
    } else {
      ApiService().setAppResumeMode('student');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    LiveClassRingService.instance.stop();
    AccessCodeService.instance.detach();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _poll(showAlerts: false);
    } else if (state == AppLifecycleState.paused) {
      _poll(showAlerts: true);
    }
  }

  void _startPolling() {
    _poll(showAlerts: false);
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      final backgrounded =
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
      _poll(showAlerts: backgrounded);
    });
  }

  Future<void> _poll({required bool showAlerts}) async {
    await refreshCommunityBadge(_api);
    await LocalNotificationService.instance.poll(_api, showAlerts: showAlerts);
    await LiveClassRingService.instance.syncWithLiveStatus(_api);
    await AccessCodeService.instance.poll(_api);
    if (mounted) setState(() {});
  }

  Future<void> _ensureStudentRole() async {
    final role = await _api.getRole();
    if (!mounted) return;
    if (role == 'kind') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const KindShell()),
      );
    }
  }

  void _onTabTap(int i) {
    setState(() => _currentIndex = i);
    if (i == 3) refreshCommunityBadge(_api);
  }

  @override
  Widget build(BuildContext context) {
    AccessCodeService.instance.attach(context);
    return Scaffold(
      backgroundColor: context.bgColor,
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: communityUnreadCount,
        builder: (context, communityBadge, _) {
          return Padding(
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
                children: List.generate(_navItems.length, (i) {
                  final active = i == _currentIndex;
                  final activeColor = context.accentColor;
                  final inactiveColor = context.greyColor;
                  final badge = i == 3 ? communityBadge : 0;
                  final item = _navItems[i];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onTabTap(i),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? activeColor.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  active ? item.activeIcon : item.icon,
                                  color: active ? activeColor : inactiveColor,
                                  size: active ? 22 : 20,
                                ),
                                if (badge > 0)
                                  Positioned(
                                    right: -8,
                                    top: -6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFEF4444),
                                            Color(0xFFF97316),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        badge > 9 ? '9+' : '$badge',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                item.label,
                                maxLines: 1,
                                style: TextStyle(
                                  color: active ? activeColor : inactiveColor,
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
          );
        },
      ),
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
