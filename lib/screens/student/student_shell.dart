import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/api_service.dart';
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

class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final _api = ApiService();
  Timer? _pollTimer;

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureStudentRole();
    _startPolling();
    LocalNotificationService.instance.init().then((_) {
      LocalNotificationService.instance.seedKnownNotifications(_api);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    LiveClassRingService.instance.stop();
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
    _pollTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      final backgrounded =
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
      _poll(showAlerts: backgrounded);
    });
  }

  Future<void> _poll({required bool showAlerts}) async {
    await refreshCommunityBadge(_api);
    await LocalNotificationService.instance.poll(_api, showAlerts: showAlerts);
    await LiveClassRingService.instance.syncWithLiveStatus(_api);
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
    return Scaffold(
      backgroundColor: context.bgColor,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: communityUnreadCount,
        builder: (context, communityBadge, _) {
          return Container(
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
                final badge = i == 3 ? communityBadge : 0;
                return GestureDetector(
                  onTap: () => _onTabTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
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
                            if (badge > 0)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    badge > 9 ? '9+' : '$badge',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(_navItems[i].label,
                            style: TextStyle(
                              color: active ? activeColor : inactiveColor,
                              fontSize: 10,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.normal,
                            )),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
