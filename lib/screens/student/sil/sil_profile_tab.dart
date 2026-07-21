import 'package:flutter/material.dart';

import 'sil_models.dart';
import 'sil_wallet_screen.dart';
import 'sil_widgets.dart';

/// Aczone-style Profile tab.
class SilProfileTab extends StatelessWidget {
  final SilProfile profile;
  final bool offline;
  final ValueChanged<SilProfile> onProfileUpdate;

  const SilProfileTab({
    super.key,
    required this.profile,
    required this.offline,
    required this.onProfileUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final xpNeed = (p.level * 350).clamp(500, 99999);
    final xpProg = (p.xp / xpNeed).clamp(0.0, 1.0);
    final played = p.wins + p.losses;

    return ColoredBox(
      color: SilColors.pageBg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
          children: [
            SilAczoneAppBar(
              onBack: () => Navigator.pop(context),
              trailing: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.settings_outlined,
                    color: SilColors.text),
              ),
            ),
            const SizedBox(height: 8),
            // Profile banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6A5AE0), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.white24,
                        child: Text(
                          p.gamerTag.isNotEmpty
                              ? p.gamerTag[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit_rounded,
                              size: 14, color: SilColors.purple),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.gamerTag.isNotEmpty ? p.gamerTag : 'Explorer',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Level ${p.level}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: xpProg,
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${p.xp} / $xpNeed XP',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.military_tech_rounded,
                      color: SilColors.gold, size: 40),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _stat(Icons.bolt_rounded, '$played', 'Quizzes Played',
                    SilColors.purple),
                _stat(Icons.emoji_events_rounded, '${p.wins}', 'Quizzes Won',
                    SilColors.gold),
                _stat(Icons.track_changes_rounded,
                    '${p.winRate.toStringAsFixed(0)}%', 'Average Score',
                    const Color(0xFFEF4444)),
                _stat(Icons.local_fire_department_rounded,
                    '${p.currentStreak}', 'Day Streak',
                    const Color(0xFFF97316)),
              ],
            ),
            SilSectionTitle(title: 'Achievements', action: 'View All', onAction: () {}),
            SizedBox(
              height: 110,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _ach('Quiz Master', Icons.shield_rounded, 'Win 10 quizzes'),
                  _ach('Speedster', Icons.timer_rounded, 'Answer 100 Qs'),
                  _ach('Perfect 10', Icons.workspace_premium_rounded,
                      'Score 100%'),
                  _ach('Knowledgeable', Icons.menu_book_rounded, 'Play 50'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _menu(Icons.bar_chart_rounded, 'My Statistics', () {}),
            const SizedBox(height: 8),
            _menu(Icons.grid_view_rounded, 'My Badges', () {}),
            const SizedBox(height: 8),
            _menu(Icons.bookmark_border_rounded, 'Saved Quizzes', () {}),
            const SizedBox(height: 8),
            _menu(Icons.account_balance_wallet_outlined, 'Coin Wallet',
                () async {
              final updated = await Navigator.push<SilProfile>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SilWalletScreen(profile: p, offline: offline),
                ),
              );
              if (updated != null) onProfileUpdate(updated);
            }),
            const SizedBox(height: 8),
            _menu(Icons.settings_outlined, 'Settings', () {}),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: SilColors.text)),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: SilColors.muted)),
        ],
      ),
    );
  }

  Widget _ach(String title, IconData icon, String sub) {
    return Container(
      width: 112,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: SilColors.purple, size: 28),
          const SizedBox(height: 6),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: SilColors.text)),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: SilColors.muted)),
        ],
      ),
    );
  }

  Widget _menu(IconData icon, String title, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: SilColors.muted, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: SilColors.text,
                        fontSize: 15)),
              ),
              const Icon(Icons.chevron_right_rounded, color: SilColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
