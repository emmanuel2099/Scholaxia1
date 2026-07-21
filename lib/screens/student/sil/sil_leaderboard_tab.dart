import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import 'sil_league_header.dart';
import 'sil_models.dart';
import 'sil_widgets.dart';

/// Rankings tab — exact mockup UI.
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
  int _tab = 0;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  static const _tabs = ['Students', 'Schools', 'Classes', 'National'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fallback = [
      {'rank': 1, 'gamer_tag': 'Alex Parker', 'school': 'King\'s College', 'score': 12560},
      {'rank': 2, 'gamer_tag': 'Sophia Lee', 'school': 'Queen\'s College', 'score': 9850},
      {'rank': 3, 'gamer_tag': 'James Wilson', 'school': 'Federal College', 'score': 8430},
      {'rank': 4, 'gamer_tag': 'Emma Johnson', 'school': 'Scholaxia Academy', 'score': 7200},
      {'rank': 5, 'gamer_tag': 'Liam Brown', 'school': 'Unity High', 'score': 6100},
      {'rank': 6, 'gamer_tag': 'Olivia Davis', 'school': 'Grace School', 'score': 5800},
      {'rank': 7, 'gamer_tag': widget.profile.gamerTag, 'school': widget.profile.schoolName.isEmpty ? 'Scholaxia Academy' : widget.profile.schoolName, 'score': widget.profile.coins.clamp(100, 99999), 'is_you': true},
      {'rank': 8, 'gamer_tag': 'Noah Garcia', 'school': 'Bright Stars', 'score': 4900},
    ];

    if (widget.offline) {
      setState(() {
        _entries = fallback;
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
          _entries = list.isEmpty ? fallback : list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = fallback;
          _loading = false;
        });
      }
    }
  }

  String _name(Map e) => e['gamer_tag']?.toString() ?? e['name']?.toString() ?? '?';
  String _school(Map e) =>
      e['school']?.toString() ?? e['school_name']?.toString() ?? 'School';
  int _score(Map e) => int.tryParse('${e['score'] ?? e['wins'] ?? 0}') ?? 0;
  int _rank(Map e, int i) =>
      int.tryParse('${e['rank'] ?? i + 1}') ?? i + 1;

  @override
  Widget build(BuildContext context) {
    final myIndex = _entries.indexWhere((e) =>
        e['is_you'] == true ||
        _name(e).toLowerCase() == widget.profile.gamerTag.toLowerCase());
    final myEntry = myIndex >= 0 ? _entries[myIndex] : null;

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: SilColors.purple))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
                children: [
                  const SilLeagueHeader(),
                  const SizedBox(height: 8),
                  const Text(
                    'Rankings',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  Text(
                    'See the top performers in the league.',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: List.generate(_tabs.length, (i) {
                      final on = _tab == i;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _tab = i),
                          child: Column(
                            children: [
                              Text(
                                _tabs[i],
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: on
                                      ? SilColors.purple
                                      : const Color(0xFF9CA3AF),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: on
                                      ? SilColors.purple
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _dropdown('JSS2 / SS1')),
                      const SizedBox(width: 10),
                      Expanded(child: _dropdown('This Week')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...List.generate(_entries.length, (i) {
                    final e = _entries[i];
                    final r = _rank(e, i);
                    final you = e['is_you'] == true ||
                        _name(e).toLowerCase() ==
                            widget.profile.gamerTag.toLowerCase();
                    return _rankRow(
                      rank: r,
                      name: you ? 'You' : _name(e),
                      school: _school(e),
                      score: _score(e),
                      highlight: you,
                    );
                  }),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SilColors.purpleSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.emoji_events_rounded,
                            color: SilColors.gold, size: 28),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Top 10 students at the end of each week win bonus coins and rewards!',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (myEntry != null) ...[
                    const SizedBox(height: 14),
                    const Text('My Rank',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 8),
                    _rankRow(
                      rank: _rank(myEntry, myIndex),
                      name: 'You',
                      school: _school(myEntry),
                      score: _score(myEntry),
                      highlight: true,
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _dropdown(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        ],
      ),
    );
  }

  Color _medal(int rank) {
    if (rank == 1) return const Color(0xFFFBBF24);
    if (rank == 2) return const Color(0xFF94A3B8);
    if (rank == 3) return const Color(0xFFD97706);
    return SilColors.purpleSoft;
  }

  Widget _rankRow({
    required int rank,
    required String name,
    required String school,
    required int score,
    bool highlight = false,
  }) {
    final medal = rank <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: highlight ? SilColors.purpleSoft : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? SilColors.purple.withOpacity(0.25) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medal ? _medal(rank) : SilColors.purpleSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: medal ? Colors.white : SilColors.purple,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor: SilColors.purpleSoft,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: SilColors.purple, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: highlight ? SilColors.purple : const Color(0xFF111827),
                    )),
                Text(school,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 11)),
              ],
            ),
          ),
          Text(
            '$score pts',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: highlight ? SilColors.purple : const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}
