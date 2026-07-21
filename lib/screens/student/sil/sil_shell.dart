import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/api_service.dart';
import 'sil_explore_tab.dart';
import 'sil_face_verify_screen.dart';
import 'sil_home_tab.dart';
import 'sil_leaderboard_tab.dart';
import 'sil_league_tab.dart';
import 'sil_models.dart';
import 'sil_profile_tab.dart';
import 'sil_widgets.dart';

class SilShell extends StatefulWidget {
  final SilProfile profile;
  final bool offline;

  const SilShell({super.key, required this.profile, this.offline = false});

  @override
  State<SilShell> createState() => _SilShellState();
}

class _SilShellState extends State<SilShell> with WidgetsBindingObserver {
  int _index = 0;
  late SilProfile _profile;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    WidgetsBinding.instance.addObserver(this);
    // Remember League so app restart returns here (not Student home).
    ApiService().setAppResumeMode('league');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _locked = true;
    } else if (state == AppLifecycleState.resumed && _locked) {
      _reverifyOnReturn();
    }
  }

  Future<void> _reverifyOnReturn() async {
    if (!mounted) return;
    final selfie = await SilFaceVerifyScreen.open(
      context,
      title: 'Re-verify identity',
      subtitle:
          'You left the app. Face verification is required before continuing League.',
      requireApi: !widget.offline,
    );
    if (!mounted) return;
    if (selfie == null) {
      await ApiService().setAppResumeMode('student');
      Navigator.pop(context);
      return;
    }
    _locked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sil_last_face_ok', DateTime.now().toIso8601String());
  }

  void _refreshProfile(SilProfile p) => setState(() => _profile = p);

  @override
  Widget build(BuildContext context) {
    final pages = [
      SilHomeTab(
        profile: _profile,
        offline: widget.offline,
        onProfileUpdate: _refreshProfile,
      ),
      SilExploreTab(
        profile: _profile,
        offline: widget.offline,
        onProfileUpdate: _refreshProfile,
      ),
      SilLeagueTab(
        profile: _profile,
        offline: widget.offline,
        onProfileUpdate: _refreshProfile,
      ),
      SilLeaderboardTab(profile: _profile, offline: widget.offline),
      SilProfileTab(
        profile: _profile,
        offline: widget.offline,
        onProfileUpdate: _refreshProfile,
      ),
    ];

    // Force light Aczone look inside League (ignore student dark theme)
    return Theme(
      data: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: SilColors.purple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            ApiService().setAppResumeMode('student');
          }
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          extendBody: true,
          body: IndexedStack(
            index: _index,
            children: pages,
          ),
          bottomNavigationBar: _AczoneBottomNav(
            index: _index,
            onTap: (i) => setState(() => _index = i),
          ),
        ),
      ),
    );
  }
}

/// White Aczone bottom bar + floating purple bolt.
class _AczoneBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _AczoneBottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 72,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 64,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(child: _item(0, Icons.home_outlined, Icons.home_rounded, 'Home')),
                  Expanded(child: _item(1, Icons.people_outline_rounded, Icons.people_rounded, 'Community')),
                  const SizedBox(width: 64),
                  Expanded(
                      child: _item(3, Icons.leaderboard_outlined,
                          Icons.leaderboard_rounded, 'Rankings')),
                  Expanded(
                      child: _item(4, Icons.person_outline_rounded,
                          Icons.person_rounded, 'Profile')),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: GestureDetector(
                onTap: () => onTap(2),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: SilColors.purple,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: SilColors.purple.withOpacity(0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.emoji_events_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, IconData active, String label) {
    final selected = index == i;
    return InkWell(
      onTap: () => onTap(i),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? active : icon,
              color: selected ? SilColors.purple : const Color(0xFF9CA3AF),
              size: 24),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? SilColors.purple : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }
}
