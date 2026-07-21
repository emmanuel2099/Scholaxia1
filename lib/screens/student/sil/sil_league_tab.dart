import 'package:flutter/material.dart';

import 'sil_invite_screen.dart';
import 'sil_league_header.dart';
import 'sil_modes_sheet.dart';
import 'sil_models.dart';
import 'sil_quiz_screen.dart';
import 'sil_wallet_screen.dart';
import 'sil_widgets.dart';

/// Center League tab — wallet, challenges, fixtures (mockup middle screen).
class SilLeagueTab extends StatelessWidget {
  final SilProfile profile;
  final bool offline;
  final ValueChanged<SilProfile> onProfileUpdate;

  const SilLeagueTab({
    super.key,
    required this.profile,
    required this.offline,
    required this.onProfileUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
          children: [
            const SilLeagueHeader(),
            const SizedBox(height: 8),
            const Text(
              'League',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            Text(
              'Compete and win amazing rewards.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B21B6), Color(0xFF6A5AE0)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('My Wallet',
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.monetization_on_rounded,
                                color: Color(0xFFFBBF24), size: 22),
                            const SizedBox(width: 6),
                            Text(
                              '${p.coins} Coins Balance',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => _openWallet(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFBBF24),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: const Size(0, 34),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Buy Coins',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 11)),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton(
                        onPressed: () => _openWallet(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Transaction',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('Choose a Challenge',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF111827))),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
              children: [
                _challengeCard(
                  context,
                  'Student Challenge',
                  'Bet coins · live duel',
                  Icons.sports_kabaddi_rounded,
                  const Color(0xFF6A5AE0),
                  'student_challenge',
                ),
                _challengeCard(
                  context,
                  'AI Challenge',
                  'Levels 1–6 vs Sia',
                  Icons.smart_toy_rounded,
                  const Color(0xFF2563EB),
                  'ai_challenge',
                ),
                _challengeCard(
                  context,
                  'Class Challenge',
                  'Represent your class',
                  Icons.groups_rounded,
                  const Color(0xFF16A34A),
                  'class_challenge',
                ),
                _challengeCard(
                  context,
                  'School Challenge',
                  'School vs school',
                  Icons.school_rounded,
                  const Color(0xFFEA580C),
                  'school_challenge',
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Upcoming Fixtures',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF111827))),
            const SizedBox(height: 10),
            _fixtureCard(
              context,
              left: 'Scholaxia Academy',
              right: 'King\'s College',
              meta: 'Today · 03:00 PM · SS1 Quiz Match',
            ),
            const SizedBox(height: 18),
            const Text('Recent Matches',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF111827))),
            const SizedBox(height: 10),
            _recentCard('You', 'Adaeze', '3', '1', '+80 coins'),
            _recentCard('Chidi', 'You', '2', '2', '+20 coins'),
          ],
        ),
      ),
    );
  }

  Widget _challengeCard(
    BuildContext context,
    String title,
    String sub,
    IconData icon,
    Color color,
    String mode,
  ) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openMode(context, mode),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFF111827))),
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fixtureCard(
    BuildContext context, {
    required String left,
    required String right,
    required String meta,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _schoolBadge(left, SilColors.purple)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('VS',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: SilColors.purple,
                        fontSize: 16)),
              ),
              Expanded(child: _schoolBadge(right, const Color(0xFF0EA5E9))),
            ],
          ),
          const SizedBox(height: 10),
          Text(meta,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _openMode(context, 'practice'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SilColors.purple,
                side: const BorderSide(color: SilColors.purple),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('View Details',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _schoolBadge(String name, Color c) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.account_balance_rounded, color: c),
        ),
        const SizedBox(height: 6),
        Text(name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
      ],
    );
  }

  Widget _recentCard(
      String a, String b, String sa, String sb, String coins) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('$a vs $b',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text('$sa-$sb',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(width: 10),
          Text(coins,
              style: const TextStyle(
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _openWallet(BuildContext context) async {
    final updated = await Navigator.push<SilProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => SilWalletScreen(profile: profile, offline: offline),
      ),
    );
    if (updated != null) onProfileUpdate(updated);
  }

  Future<void> _openMode(BuildContext context, String id) async {
    if (id == 'student_challenge' ||
        id == 'class_challenge' ||
        id == 'school_challenge') {
      await SilInviteScreen.open(
        context,
        mode: id,
        profile: profile,
      );
      return;
    }
    if (id == 'ai_challenge') {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => SilModesSheet(
          mode: id,
          profile: profile,
          offline: offline,
          onProfileUpdate: onProfileUpdate,
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SilQuizScreen(
          mode: id,
          subject: 'General Knowledge',
          profile: profile,
          offline: offline,
          onProfileUpdate: onProfileUpdate,
        ),
      ),
    );
  }
}
