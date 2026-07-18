import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_models.dart';
import 'sil_widgets.dart';

class SilLeaderboardTab extends StatefulWidget {
  final SilProfile profile;
  final bool offline;

  const SilLeaderboardTab({
    super.key,
    required this.profile,
    required this.offline,
  });

  @override
  State<SilLeaderboardTab> createState() => _SilLeaderboardTabState();
}

class _SilLeaderboardTabState extends State<SilLeaderboardTab> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.offline) {
      setState(() {
        _entries = [
          {'rank': 1, 'gamer_tag': widget.profile.gamerTag, 'score': 12560, 'wins': widget.profile.wins},
          {'rank': 2, 'gamer_tag': 'Sophia Lee', 'score': 9850, 'wins': 40},
          {'rank': 3, 'gamer_tag': 'James Wilson', 'score': 8430, 'wins': 32},
          {'rank': 4, 'gamer_tag': 'Emma Johnson', 'score': 7200, 'wins': 28},
          {'rank': 5, 'gamer_tag': 'Liam Brown', 'score': 6100, 'wins': 21},
        ];
        _loading = false;
      });
      return;
    }
    try {
      final data = await ApiService().silLeaderboard();
      final list = (data['entries'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          _entries = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top3 = _entries.take(3).toList();
    final rest = _entries.length > 3 ? _entries.sublist(3) : <Map<String, dynamic>>[];

    return SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: SilColors.purple))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text('Leaderboard',
                    style: TextStyle(
                        color: context.textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w900)),
                Text('Top players this week',
                    style: TextStyle(color: context.greyColor)),
                const SizedBox(height: 20),
                if (top3.isNotEmpty)
                  SizedBox(
                    height: 180,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (top3.length > 1) Expanded(child: _podium(context, top3[1], 2, 110)),
                        Expanded(child: _podium(context, top3[0], 1, 140)),
                        if (top3.length > 2) Expanded(child: _podium(context, top3[2], 3, 90)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                ...rest.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? const Color(0xFF1A1228)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Text('${e['rank']}',
                              style: TextStyle(
                                  color: context.greyColor,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(width: 12),
                          CircleAvatar(
                            backgroundColor: SilColors.purpleSoft,
                            child: Text(
                              (e['gamer_tag']?.toString() ?? '?')[0].toUpperCase(),
                              style: const TextStyle(
                                  color: SilColors.purple,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(e['gamer_tag']?.toString() ?? '',
                                style: TextStyle(
                                    color: context.textColor,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Text('${e['score'] ?? e['wins']}',
                              style: const TextStyle(
                                  color: SilColors.purple,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [SilColors.purpleDeep, SilColors.purple],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'Keep playing quizzes to climb the leaderboard!',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _podium(
      BuildContext context, Map<String, dynamic> e, int place, double h) {
    final colors = {
      1: SilColors.gold,
      2: const Color(0xFF94A3B8),
      3: const Color(0xFFD97706),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        CircleAvatar(
          radius: place == 1 ? 28 : 22,
          backgroundColor: SilColors.purpleSoft,
          child: Text(
            (e['gamer_tag']?.toString() ?? '?')[0].toUpperCase(),
            style: const TextStyle(
                color: SilColors.purple, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 6),
        Text(e['gamer_tag']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: context.textColor,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
        Text('${e['score'] ?? e['wins']}',
            style: TextStyle(
                color: colors[place],
                fontWeight: FontWeight.w800,
                fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: SilColors.purple.withOpacity(place == 1 ? 0.9 : 0.55),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 8),
          child: Text('#$place',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}
