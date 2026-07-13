import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/student_ui.dart';
import '../../widgets/app_header_actions.dart';
import 'kind_learn_screen.dart';
import 'kind_cbt_screen.dart';
import 'kind_shared.dart';

class KindHomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigate;

  const KindHomeScreen({super.key, this.onNavigate});

  @override
  State<KindHomeScreen> createState() => _KindHomeScreenState();
}

class _KindHomeScreenState extends State<KindHomeScreen> {
  final _api = ApiService();
  String _name = 'Friend';
  String _ageGroup = '';
  int _liveCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.getKindMe(),
        _api.listLiveClasses(status: 'live'),
      ]);
      final p = results[0] as Map<String, dynamic>;
      final raw = results[1] as List<dynamic>;
      final live = raw
          .whereType<Map>()
          .where((c) => c['is_live'] == true)
          .length;
      if (!mounted) return;
      final full = p['full_name']?.toString() ?? 'Friend';
      setState(() {
        _name = full.split(' ').first;
        _ageGroup = p['age_group']?.toString() ?? '';
        _liveCount = live;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openLearn() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KindLearnScreen()),
    );
  }

  void _openCbt() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KindCbtScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.accentColor))
          : RefreshIndicator(
              color: context.accentColor,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Scholaxia Kids',
                                    style: TextStyle(
                                      color: context.textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const AppHeaderActions(),
                              ],
                            ),
                          ),
                          KindHeroHeader(
                            greeting: 'Hi, $_name!',
                            subtitle: _ageGroup.isNotEmpty
                                ? 'Ages $_ageGroup · Ready to learn something fun today?'
                                : 'Welcome back — pick an adventure below!',
                            badge: 'KID SAFE',
                          ),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              height: 110,
                              child: Row(
                                children: [
                                  StudentStatCard(
                                  icon: Icons.videocam_rounded,
                                  value: '$_liveCount',
                                  label: 'Live now',
                                  gradient: const [
                                    Color(0xFFA855F7),
                                    Color(0xFFD946EF),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                StudentStatCard(
                                  icon: Icons.auto_awesome_rounded,
                                  value: 'Sia',
                                  label: 'AI tutor',
                                  gradient: const [
                                    Color(0xFF7C3AED),
                                    Color(0xFF9333EA),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                StudentStatCard(
                                  icon: Icons.menu_book_rounded,
                                  value: 'Learn',
                                  label: '& play',
                                  gradient: const [
                                    Color(0xFF10B981),
                                    Color(0xFF34D399),
                                  ],
                                ),
                              ],
                            ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          StudentFeatureBanner(
                            title: 'Chat with Sia',
                            subtitle:
                                'Homework help, fun facts, and stories — made just for kids.',
                            buttonLabel: 'Start chatting',
                            icon: Icons.auto_awesome_rounded,
                            onTap: () => widget.onNavigate?.call(1),
                          ),
                          _quickAccess(context),
                          _kidSafeBanner(context),
                          const SizedBox(height: 110),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _quickAccess(BuildContext context) {
    final items = [
      (
        Icons.videocam_rounded,
        'Live Class',
        'Join your teacher\'s lesson.',
        const [Color(0xFFA855F7), Color(0xFFD946EF)],
        () => widget.onNavigate?.call(2),
      ),
      (
        Icons.video_library_rounded,
        'Saved Class',
        'Replay saved lessons.',
        const [Color(0xFF6366F1), Color(0xFF818CF8)],
        () => widget.onNavigate?.call(3),
      ),
      (
        Icons.videogame_asset_rounded,
        'Games',
        '30+ fun learning games.',
        const [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
        () => widget.onNavigate?.call(4),
      ),
      (
        Icons.menu_book_rounded,
        'Learn',
        'Mini-lessons for your age.',
        const [Color(0xFF10B981), Color(0xFF34D399)],
        _openLearn,
      ),
      (
        Icons.quiz_rounded,
        'Quiz',
        'Fun questions on any topic.',
        const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
        _openLearn,
      ),
      (
        Icons.assignment_rounded,
        'Entrance CBT',
        'Primary 6 Common Entrance.',
        const [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
        _openCbt,
      ),
      (
        Icons.auto_awesome_rounded,
        'Sia AI',
        'Ask anything you\'re curious about.',
        const [Color(0xFF7C3AED), Color(0xFF9333EA)],
        () => widget.onNavigate?.call(1),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StudentSectionTitle(title: 'Quick Access'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.92,
            children: items.map((a) {
              return StudentQuickTile(
                icon: a.$1,
                label: a.$2,
                subtitle: a.$3,
                gradient: a.$4,
                onTap: a.$5,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _kidSafeBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.isDark
                ? [const Color(0xFF1A1428), const Color(0xFF221A35)]
                : [Colors.white, const Color(0xFFF3EEFF)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: context.accentColor.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppGradients.primaryButton,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.shield_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Sia Kind is kid-safe — designed for learners ages 3–12.',
                style: TextStyle(
                  color: context.greyLColor,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
