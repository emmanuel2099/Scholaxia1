import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import 'kind_shared.dart';

class KindHomeScreen extends StatefulWidget {
  const KindHomeScreen({super.key});

  @override
  State<KindHomeScreen> createState() => _KindHomeScreenState();
}

class _KindHomeScreenState extends State<KindHomeScreen> {
  final _api = ApiService();
  String _name = 'Friend';
  String _ageGroup = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _api.getKindMe();
      if (!mounted) return;
      final full = p['full_name']?.toString() ?? 'Friend';
      setState(() {
        _name = full.split(' ').first;
        _ageGroup = p['age_group']?.toString() ?? '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: KidColors.accent))
            : RefreshIndicator(
                color: KidColors.accent,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: KidColors.accent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.child_care,
                              color: KidColors.accent, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Hi, $_name!',
                                  style: TextStyle(
                                      color: context.textColor,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                _ageGroup.isNotEmpty
                                    ? 'Ages $_ageGroup · Kid learner'
                                    : 'Welcome to Scholaxia Kids',
                                style: TextStyle(
                                    color: context.greyColor, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text('What do you want to do?',
                        style: TextStyle(
                            color: context.textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    _card(
                      context,
                      icon: Icons.auto_awesome,
                      title: 'Chat with Sia',
                      subtitle: 'Ask anything — homework, stories, or fun facts.',
                      color: KidColors.accent,
                    ),
                    const SizedBox(height: 12),
                    _card(
                      context,
                      icon: Icons.menu_book_rounded,
                      title: 'Learn something new',
                      subtitle: 'Mini-lessons made just for your age.',
                      color: KidColors.learn,
                    ),
                    const SizedBox(height: 12),
                    _card(
                      context,
                      icon: Icons.quiz_outlined,
                      title: 'Play a quiz',
                      subtitle: 'Fun questions on topics you pick.',
                      color: KidColors.quiz,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: KidColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: KidColors.accent.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              color: KidColors.accent, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Sia Kind is kid-safe — made for learners ages 3–12.',
                              style: TextStyle(
                                  color: context.greyLColor,
                                  fontSize: 12,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: context.textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: context.greyColor, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
