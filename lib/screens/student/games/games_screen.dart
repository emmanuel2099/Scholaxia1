import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import '../sil/sil_entry.dart';
import 'math_arena_screen.dart';
import 'spelling_bee_screen.dart';
import 'word_arrangement_screen.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = [
      _GameData(
        title: 'Spelling Bee',
        subtitle: 'Deep vocabulary. Strict timer. No mercy.',
        icon: Icons.spellcheck_rounded,
        gradient: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
        screen: const SpellingBeeScreen(),
      ),
      _GameData(
        title: 'Math Arena',
        subtitle: 'Hard equations. Solve x in real time.',
        icon: Icons.functions_rounded,
        gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        screen: const MathArenaScreen(),
      ),
      _GameData(
        title: 'Word Arrangement',
        subtitle: 'Unscramble brutal sentences fast.',
        icon: Icons.reorder_rounded,
        gradient: const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
        screen: const WordArrangementScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Text(
                    'Games',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B21B6), Color(0xFF7C3AED)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 8),
                  const Text(
                    'Scholaxia Intellect League',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Live competitions · coins · rankings · school pride.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SilEntryScreen()),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Enter League',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppGradients.hero(context),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎮', style: TextStyle(fontSize: 30)),
                  const SizedBox(height: 8),
                  const Text(
                    'Brain Breakers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Three very hard games — 30 levels each, no repeated questions.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const StudentSectionTitle(title: 'Pick a challenge'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: games
                    .map(
                      (g) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _GameTile(
                          data: g,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => g.screen),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameData {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final Widget screen;
  const _GameData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.screen,
  });
}

class _GameTile extends StatefulWidget {
  final _GameData data;
  final VoidCallback onTap;
  const _GameTile({required this.data, required this.onTap});

  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.data.gradient.first;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _pressed
              ? Color.alphaBlend(accent.withOpacity(0.18), context.cardColor)
              : context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _pressed ? accent : context.borderColor,
            width: _pressed ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(_pressed ? 0.3 : 0.12),
              blurRadius: _pressed ? 16 : 8,
              offset: Offset(0, _pressed ? 6 : 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: widget.data.gradient),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(widget.data.icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.data.title,
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.data.subtitle,
                    style: TextStyle(
                      color: context.greyColor,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.greyColor),
          ],
        ),
      ),
    );
  }
}
