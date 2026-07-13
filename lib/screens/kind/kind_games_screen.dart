import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/student_ui.dart';
import 'kind_game_screen.dart';
import 'kind_leaf_progress.dart';
import 'kind_shared.dart';

class KindGamesScreen extends StatefulWidget {
  const KindGamesScreen({super.key});

  @override
  State<KindGamesScreen> createState() => _KindGamesScreenState();
}

class _KindGamesScreenState extends State<KindGamesScreen> {
  final Map<String, int> _leaves = {};

  @override
  void initState() {
    super.initState();
    _loadLeaves();
  }

  Future<void> _loadLeaves() async {
    final map = <String, int>{};
    for (final g in kidGames) {
      map[g.id] = await KindLeafProgress.leafLevel(g.id);
    }
    if (mounted) setState(() => _leaves.addAll(map));
  }

  Future<void> _openGame(KidGame g) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KindGameScreen(
          gameId: g.id,
          title: g.title,
          subtitle: g.subtitle,
          icon: g.icon,
          gradient: g.gradient,
          questionBuilder: g.builder,
        ),
      ),
    );
    _loadLeaves();
  }

  @override
  Widget build(BuildContext context) {
    final games = kidGames;

    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            KindHeroHeader(
              greeting: 'Educational Games',
              subtitle:
                  'Play to unlock Leaf 2… Leaf 30. Each game has 50+ questions and works offline.',
              icon: Icons.videogame_asset_rounded,
              badge: 'KID SAFE',
            ),
            const StudentSectionTitle(title: 'Pick a game'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.82,
                children: games.map((g) {
                  final leaf = _leaves[g.id] ?? 1;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: StudentQuickTile(
                          icon: g.icon,
                          label: g.title,
                          subtitle: 'Leaf $leaf · ${g.subtitle}',
                          gradient: g.gradient,
                          onTap: () => _openGame(g),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.eco_rounded,
                                  size: 14, color: g.gradient.first),
                              const SizedBox(width: 2),
                              Text(
                                '$leaf',
                                style: TextStyle(
                                  color: g.gradient.first,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
