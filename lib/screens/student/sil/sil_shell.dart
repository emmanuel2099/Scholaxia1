import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/app_theme.dart';
import 'sil_explore_tab.dart';
import 'sil_face_verify_screen.dart';
import 'sil_home_tab.dart';
import 'sil_leaderboard_tab.dart';
import 'sil_models.dart';
import 'sil_profile_tab.dart';
import 'sil_quiz_screen.dart';
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
      Navigator.pop(context);
      return;
    }
    _locked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sil_last_face_ok', DateTime.now().toIso8601String());
  }

  void _refreshProfile(SilProfile p) => setState(() => _profile = p);

  Future<void> _quickPlay() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SilQuizScreen(
          mode: 'practice',
          subject: 'General Knowledge',
          profile: _profile,
          offline: widget.offline,
          onProfileUpdate: _refreshProfile,
        ),
      ),
    );
  }

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
      const SizedBox.shrink(),
      SilLeaderboardTab(profile: _profile, offline: widget.offline),
      SilProfileTab(
        profile: _profile,
        offline: widget.offline,
        onProfileUpdate: _refreshProfile,
      ),
    ];

    return Scaffold(
      backgroundColor: context.bgColor,
      body: IndexedStack(
        index: _index == 2 ? 0 : _index,
        children: [
          pages[0],
          pages[1],
          pages[0],
          pages[3],
          pages[4],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: context.isDark ? const Color(0xFF1A1228) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: SilColors.purple.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _nav(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
              _nav(1, Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
              _centerPlay(),
              _nav(3, Icons.emoji_events_outlined, Icons.emoji_events_rounded,
                  'Ranks'),
              _nav(4, Icons.person_outline_rounded, Icons.person_rounded,
                  'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nav(int i, IconData icon, IconData active, String label) {
    final selected = _index == i;
    return InkWell(
      onTap: () => setState(() => _index = i),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? active : icon,
                color: selected ? SilColors.purple : context.greyColor,
                size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? SilColors.purple : context.greyColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerPlay() {
    return GestureDetector(
      onTap: _quickPlay,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: SilColors.purple,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: SilColors.purple.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 30),
      ),
    );
  }
}
