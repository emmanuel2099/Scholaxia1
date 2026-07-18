import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'sil_models.dart';
import 'sil_wallet_screen.dart';
import 'sil_widgets.dart';

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
    final xpNeed = p.level * 350;
    final xpProg = (p.xp / xpNeed).clamp(0.0, 1.0);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('League Profile',
              style: TextStyle(
                  color: context.textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [SilColors.purpleDeep, SilColors.purple],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 10),
                Text(p.gamerTag,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                Text('Level ${p.level} · ${p.academicClass}',
                    style: TextStyle(color: Colors.white.withOpacity(0.9))),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: xpProg,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    color: SilColors.gold,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${p.xp} / $xpNeed XP',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat(context, '${p.wins + p.losses}', 'Played', Icons.bolt),
              _stat(context, '${p.wins}', 'Won', Icons.emoji_events),
              _stat(context, '${p.winRate.toStringAsFixed(0)}%', 'Win rate',
                  Icons.track_changes),
              _stat(context, '${p.currentStreak}', 'Streak', Icons.local_fire_department),
            ],
          ),
          const SilSectionTitle(title: 'Achievements'),
          SizedBox(
            height: 88,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: (p.badges.isEmpty ? ['New Challenger'] : p.badges)
                  .map((b) => Container(
                        width: 100,
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: SilColors.purpleSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.military_tech_rounded,
                                color: SilColors.purple),
                            const SizedBox(height: 6),
                            Text(b,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          _menu(context, Icons.account_balance_wallet_rounded, 'Wallet & Coins',
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
          _menu(context, Icons.school_rounded, p.schoolName, null),
          _menu(context, Icons.place_rounded, '${p.state}, ${p.country}', null),
          _menu(
              context,
              p.faceVerified ? Icons.verified_user : Icons.gpp_maybe,
              p.faceVerified ? 'Face verified' : 'Face not verified',
              null),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Offline mode — sync when API is available.',
                  style: TextStyle(color: context.greyColor, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String v, String l, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: SilColors.purple, size: 20),
          const SizedBox(height: 4),
          Text(v,
              style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 16)),
          Text(l, style: TextStyle(color: context.greyColor, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _menu(
      BuildContext context, IconData icon, String title, VoidCallback? onTap) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: SilColors.purple),
      title: Text(title,
          style: TextStyle(
              color: context.textColor, fontWeight: FontWeight.w600)),
      trailing: onTap != null
          ? const Icon(Icons.chevron_right_rounded)
          : null,
    );
  }
}
