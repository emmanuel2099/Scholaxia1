import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_modes_sheet.dart';
import 'sil_models.dart';
import 'sil_quiz_screen.dart';
import 'sil_wallet_screen.dart';
import 'sil_widgets.dart';

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
  Map<String, dynamic>? _dash;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.offline) return;
    try {
      final d = await ApiService().silDashboard();
      if (mounted) setState(() => _dash = d);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final modes = (_dash?['modes'] as List?) ??
        [
          {'id': 'practice', 'title': 'Practice Mode', 'subtitle': 'No risk'},
          {'id': 'ai_challenge', 'title': 'Play vs Computer', 'subtitle': 'Levels 1–6'},
          {'id': 'student_challenge', 'title': 'Challenge Student', 'subtitle': 'Live bets'},
          {'id': 'friday_national', 'title': 'Friday National', 'subtitle': 'Weekly'},
        ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back_rounded, color: context.textColor),
                ),
                Expanded(
                  child: Text(
                    'Scholaxia League',
                    style: TextStyle(
                      color: context.textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                GestureDetector(
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
                  child: SilCoinChip(coins: p.coins),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              'Hi, ${p.gamerTag}! 👋',
              style: TextStyle(
                color: context.textColor,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'What do you want to compete in today?',
              style: TextStyle(color: context.greyColor, fontSize: 14),
            ),
          ),
          if (_dash?['friday_live'] == true)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [SilColors.purpleDeep, SilColors.purple],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Friday National Challenge is LIVE',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openMode('friday_national'),
                    child: const Text('Join',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          const SilSectionTitle(title: 'Competition modes'),
          ...modes.map((m) {
            final map = Map<String, dynamic>.from(m as Map);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Material(
                color: context.isDark
                    ? const Color(0xFF1A1228)
                    : Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _openMode(map['id']?.toString() ?? 'practice'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: SilColors.purpleSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.bolt_rounded,
                              color: SilColors.purple),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                map['title']?.toString() ?? '',
                                style: TextStyle(
                                  color: context.textColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                map['subtitle']?.toString() ?? '',
                                style: TextStyle(
                                    color: context.greyColor, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: SilColors.purple),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SilSectionTitle(title: 'Continue playing'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SilColors.purpleSoft.withOpacity(0.5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Practice Quiz',
                            style: TextStyle(
                                color: context.textColor,
                                fontWeight: FontWeight.w800)),
                        Text('Level ${p.aiLevel} · ready when you are',
                            style: TextStyle(
                                color: context.greyColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _openMode('practice'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SilColors.purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMode(String id) async {
    if (id == 'ai_challenge' ||
        id == 'student_challenge' ||
        id == 'class_challenge' ||
        id == 'school_challenge') {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.bgColor,
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
