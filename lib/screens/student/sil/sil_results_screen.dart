import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_models.dart';
import 'sil_widgets.dart';

class SilResultsScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  final String subject;
  final SilProfile profile;

  const SilResultsScreen({
    super.key,
    required this.result,
    required this.subject,
    required this.profile,
  });

  @override
  State<SilResultsScreen> createState() => _SilResultsScreenState();
}

class _SilResultsScreenState extends State<SilResultsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareWinToCommunity();
    });
  }

  Future<void> _shareWinToCommunity() async {
    final won = widget.result['won'] == true;
    final coins = (widget.result['coins_earned'] as num?)?.toInt() ?? 0;
    // Skip if backend already posted
    if (!won || widget.result['community_posted'] == true) return;
    try {
      final api = ApiService();
      final channels = await api.communityChannels();
      if (channels.isEmpty) return;
      final channelId = channels.first is Map
          ? (channels.first as Map)['id']?.toString()
          : null;
      if (channelId == null || channelId.isEmpty) return;
      final text =
          '🏆 ${widget.profile.gamerTag} won in Scholaxia Intellect League (${widget.subject})! '
          '${coins > 0 ? 'Earned $coins coins. ' : ''}'
          'Representing ${widget.profile.schoolName} · ${widget.profile.academicClass}. '
          '#ScholaxiaLeague';
      await api.createPost(channelId: channelId, content: text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Win posted to Community!')),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final subject = widget.subject;
    final profile = widget.profile;
    final correct = (result['correct'] as num?)?.toInt() ?? 0;
    final total = (result['total'] as num?)?.toInt() ?? 0;
    final scorePct = total == 0 ? 0 : ((correct / total) * 100).round();
    final coins = (result['coins_earned'] as num?)?.toInt() ?? 0;
    final streak = (result['longest_streak'] as num?)?.toInt() ?? 0;
    final ms = (result['time_taken_ms'] as num?)?.toInt() ?? 0;
    final mins = (ms ~/ 1000) ~/ 60;
    final secs = (ms ~/ 1000) % 60;
    final timeStr =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    final won = result['won'] == true;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.bgColor,
        elevation: 0,
        title: Text('Results',
            style: TextStyle(
                color: context.textColor, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: _shareWinToCommunity,
            icon: Icon(Icons.share_rounded, color: context.textColor),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [SilColors.purpleDeep, SilColors.purple],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_rounded, color: SilColors.gold, size: 72),
                SizedBox(height: 8),
                Text('Great Job!',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900)),
                Text('You completed the quiz.',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF1A1228) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _row(context, Icons.gps_fixed, 'Correct', '$correct/$total'),
                _row(context, Icons.check_circle, 'Score', '$scorePct%'),
                _row(context, Icons.timer_outlined, 'Time Taken', timeStr),
                _row(context, Icons.local_fire_department, 'Longest Streak',
                    '$streak'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SilColors.purpleSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on_rounded,
                    color: SilColors.gold, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    coins > 0
                        ? 'You earned $coins coins!'
                        : 'Practice complete — no coins at risk.',
                    style: TextStyle(
                      color: context.textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (won) ...[
            const SizedBox(height: 12),
            Text(
              'Your win is shared to Student Community so classmates can like & celebrate.',
              style: TextStyle(color: context.greyColor, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SilPrimaryButton(
            label: 'Play Again',
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: SilColors.purple,
              side: const BorderSide(color: SilColors.purple),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
            ),
            child: const Text('Back to League Home',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: SilColors.purple),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: TextStyle(color: context.greyColor))),
          Text(value,
              style: TextStyle(
                  color: context.textColor, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
