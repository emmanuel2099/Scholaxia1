import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import 'sil_invite_screen.dart';
import 'sil_modes_sheet.dart';
import 'sil_models.dart';
import 'sil_quiz_screen.dart';
import 'sil_wallet_screen.dart';
import 'sil_widgets.dart';

/// Exact Scholaxia Intellect League home (mockup 3) — white bg, school hero image.
class SilHomeTab extends StatefulWidget {
  final SilProfile profile;
  final bool offline;
  final ValueChanged<SilProfile> onProfileUpdate;

  const SilHomeTab({
    super.key,
    required this.profile,
    required this.offline,
    required this.onProfileUpdate,
  });

  @override
  State<SilHomeTab> createState() => _SilHomeTabState();
}

class _SilHomeTabState extends State<SilHomeTab> {
  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final name = p.gamerTag.isNotEmpty ? p.gamerTag : 'Explorer';
    final school =
        p.schoolName.isNotEmpty ? p.schoolName : 'Scholaxia Academy';
    final rank = p.nationalRank > 0 ? p.nationalRank : 42;
    final state = p.state.isNotEmpty ? p.state : 'Rivers State';
    final winRate = p.wins + p.losses == 0
        ? 0
        : ((p.wins / (p.wins + p.losses)) * 100).round();

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
          children: [
            _header(context),
            const SizedBox(height: 12),
            _greetingRow(context, p, name),
            const SizedBox(height: 14),
            _fridayHero(),
            const SizedBox(height: 14),
            _profileStatsCard(p, school, rank, state, winRate),
            const SizedBox(height: 18),
            _sectionHead('Quick Actions', 'All Actions >'),
            const SizedBox(height: 10),
            _quickActions(),
            const SizedBox(height: 18),
            _liveAndFixtures(),
            const SizedBox(height: 18),
            _leaderboards(),
            const SizedBox(height: 14),
            _latestUpdateBanner(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: () {
            ApiService().setAppResumeMode('student');
            Navigator.pop(context);
          },
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF1F2937)),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: SilColors.purple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scholaxia',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: Color(0xFF111827),
                          height: 1.1)),
                  Text('Intellect League',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          color: SilColors.purple,
                          height: 1.1)),
                ],
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded,
                  color: Color(0xFF1F2937)),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Text('3',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _greetingRow(BuildContext context, SilProfile p, String name) {
    final h = DateTime.now().hour;
    final greet = h < 12
        ? 'Good Morning'
        : h < 17
            ? 'Good Afternoon'
            : 'Good Evening';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greet, $name! 👋',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Ready to compete today?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              Text(
                'Learn. Compete. Win. Represent your school.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final updated = await Navigator.push<SilProfile>(
                context,
                MaterialPageRoute(
                  builder: (_) => SilWalletScreen(
                    profile: p,
                    offline: widget.offline,
                  ),
                ),
              );
              if (updated != null) widget.onProfileUpdate(updated);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on_rounded,
                      color: Color(0xFFFBBF24), size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${p.coins} Coins',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: Color(0xFF9CA3AF)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fridayHero() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF2E1065), Color(0xFF5B21B6), Color(0xFF6A5AE0)],
        ),
        boxShadow: [
          BoxShadow(
            color: SilColors.purple.withOpacity(0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Hero image on the right (4th image)
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.48,
              heightFactor: 1,
              child: Image.asset(
                'asset/images/sil_friday_hero.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          // Fade so text stays readable
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.55,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF5B21B6),
                      const Color(0xFF5B21B6).withOpacity(0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'UPCOMING',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Friday National Challenge 🏆',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The biggest academic battle among students across Nigeria.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 10,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _timerBox('05', 'Days'),
                    const SizedBox(width: 5),
                    _timerBox('14', 'Hours'),
                    const SizedBox(width: 5),
                    _timerBox('32', 'Mins'),
                    const SizedBox(width: 5),
                    _timerBox('20', 'Secs'),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _openMode('friday_national'),
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
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Register Now',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 12)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded, size: 14),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _openMode('friday_national'),
                      child: const Text(
                        'View Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timerBox(String v, String u) {
    return Container(
      width: 42,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B4B).withOpacity(0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(v,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  height: 1)),
          Text(u,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 8,
                  height: 1.2)),
        ],
      ),
    );
  }

  Widget _profileStatsCard(
    SilProfile p,
    String school,
    int rank,
    String state,
    int winRate,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: SilColors.purpleSoft,
                    child: Text(
                      p.gamerTag.isNotEmpty
                          ? p.gamerTag[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                        color: SilColors.purple,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: SilColors.purple,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit_rounded,
                          size: 10, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.gamerTag,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: SilColors.purpleSoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            p.academicClass,
                            style: const TextStyle(
                              color: SilColors.purple,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.shield_rounded,
                            size: 12, color: SilColors.purple),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            school,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '#$rank $state Rank',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '🔥 ${p.currentStreak} Win Streak',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          const SizedBox(height: 10),
          Row(
            children: [
              _statCol('🏆', '${p.wins}', 'Wins'),
              _statCol('💢', '${p.losses}', 'Losses'),
              _statCol('📈', '$winRate%', 'Win Rate'),
              _statCol('💰', '${p.coins}', 'Coins'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCol(String emoji, String v, String l) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          Text(v,
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: Color(0xFF111827))),
          Text(l,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _sectionHead(String title, String action) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
        ),
        Text(
          action,
          style: const TextStyle(
            color: SilColors.purple,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _quickActions() {
    final items = [
      ('Student Challenge', Icons.sports_kabaddi_rounded, const Color(0xFF6A5AE0),
          'student_challenge'),
      ('AI Challenge', Icons.smart_toy_rounded, const Color(0xFF2563EB),
          'ai_challenge'),
      ('Class Challenge', Icons.groups_rounded, const Color(0xFF16A34A),
          'class_challenge'),
      ('School Challenge', Icons.school_rounded, const Color(0xFFEA580C),
          'school_challenge'),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.55,
      children: items.map((a) {
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openMode(a.$4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: a.$3.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(a.$2, color: a.$3, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      a.$1,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _liveAndFixtures() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Live Matches',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF111827))),
              const SizedBox(height: 8),
              _liveMatchTile('King\'s College', 'Queen\'s College', '2', '1',
                  '32:14'),
              const SizedBox(height: 8),
              _liveMatchTile('Scholaxia', 'Federal Col.', '1', '1', '18:02'),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Today's Fixtures",
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF111827))),
              const SizedBox(height: 8),
              _fixtureTile('10:00 AM', 'JSS2', 'Scholaxia vs King\'s'),
              const SizedBox(height: 8),
              _fixtureTile('02:00 PM', 'SS1', 'Federal vs Queen\'s'),
              const SizedBox(height: 8),
              _fixtureTile('07:00 PM', 'NATIONAL', 'Friday Warm-up'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _liveMatchTile(
      String a, String b, String sa, String sb, String time) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _miniSchool(a, SilColors.purple)),
              Column(
                children: [
                  Text('$sa-$sb',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14)),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 8,
                            fontWeight: FontWeight.w800)),
                  ),
                  Text(time,
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 9)),
                ],
              ),
              Expanded(child: _miniSchool(b, const Color(0xFF0EA5E9))),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 28,
            child: ElevatedButton.icon(
              onPressed: () => _openMode('practice'),
              icon: const Icon(Icons.play_arrow_rounded, size: 14),
              label: const Text('Watch Live',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: SilColors.purple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniSchool(String name, Color c) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.account_balance_rounded, color: c, size: 14),
        ),
        const SizedBox(height: 2),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _fixtureTile(String time, String tag, String title) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(time,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: SilColors.purple)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SilColors.purpleSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tag,
                    style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: SilColors.purple)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: Color(0xFF111827))),
        ],
      ),
    );
  }

  Widget _leaderboards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Top Schools',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF111827))),
              const SizedBox(height: 8),
              _rankRow('1', 'King\'s College', '12,450'),
              _rankRow('2', 'Queen\'s College', '11,820'),
              _rankRow('3', 'Scholaxia Academy', '10,640'),
              _rankRow('4', 'Federal College', '9,210'),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Top Students',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF111827))),
              const SizedBox(height: 8),
              _studentRow('1', 'David O.', '2,560'),
              _studentRow('2', 'Sarah K.', '2,410'),
              _studentRow('3', 'Emma J.', '2,180'),
              _studentRow('4', 'Chidi M.', '1,990'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rankRow(String r, String name, String pts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: SilColors.purpleSoft,
            child: Text(r,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: SilColors.purple)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.account_balance_rounded,
              size: 14, color: SilColors.purple),
          const SizedBox(width: 4),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          Text(pts,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: SilColors.purple)),
        ],
      ),
    );
  }

  Widget _studentRow(String r, String name, String pts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Text(r,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF9CA3AF))),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 10,
            backgroundColor: SilColors.purpleSoft,
            child: Text(name[0],
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: SilColors.purple)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          Text(pts,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: SilColors.purple)),
        ],
      ),
    );
  }

  Widget _latestUpdateBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SilColors.purpleSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign_rounded, color: SilColors.purple, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Registration for Friday National Challenge is now open!',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _openMode('friday_national'),
            child: const Text(
              'Join Now >',
              style: TextStyle(
                color: SilColors.purple,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMode(String id) async {
    if (id == 'student_challenge' ||
        id == 'class_challenge' ||
        id == 'school_challenge') {
      await SilInviteScreen.open(
        context,
        mode: id,
        profile: widget.profile,
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
          profile: widget.profile,
          offline: widget.offline,
          onProfileUpdate: widget.onProfileUpdate,
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SilQuizScreen(
          mode: id,
          subject: id == 'friday_national'
              ? 'Friday National'
              : 'General Knowledge',
          profile: widget.profile,
          offline: widget.offline,
          onProfileUpdate: widget.onProfileUpdate,
        ),
      ),
    );
  }
}
