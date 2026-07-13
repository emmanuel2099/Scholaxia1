import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/live_join_helper.dart';
import '../../widgets/student_ui.dart';
import '../student/subscription/subscription_screen.dart';
import 'kind_booking_screen.dart';
import 'kind_shared.dart';

class KindLiveScreen extends StatefulWidget {
  const KindLiveScreen({super.key});

  @override
  State<KindLiveScreen> createState() => _KindLiveScreenState();
}

class _KindLiveScreenState extends State<KindLiveScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _live = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.listLiveClasses(status: 'live');
      if (mounted) {
        setState(() {
          _live = raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((c) => c['is_live'] == true)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: RefreshIndicator(
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
                    KindHeroHeader(
                      greeting: 'Live Class',
                      subtitle: 'Join your teacher\'s lesson with a class code.',
                      icon: Icons.videocam_rounded,
                      badge: _live.isNotEmpty ? '${_live.length} LIVE' : null,
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => joinLiveWithAccessCode(context, _api),
                          borderRadius: BorderRadius.circular(18),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: AppGradients.primaryButton,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: context.accentColor.withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 20),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.vpn_key_rounded,
                                      color: Colors.white, size: 22),
                                  SizedBox(width: 10),
                                  Text(
                                    'Enter class code',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const StudentSectionTitle(title: 'Live now'),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_live.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: context.isDark
                                  ? [
                                      const Color(0xFF1A1428),
                                      const Color(0xFF221A35),
                                    ]
                                  : [
                                      Colors.white,
                                      const Color(0xFFF3EEFF),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.videocam_off_outlined,
                                  color: context.greyColor, size: 40),
                              const SizedBox(height: 12),
                              Text(
                                'No live classes right now',
                                style: TextStyle(
                                  color: context.textColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Ask your teacher for a class code to join.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: context.greyColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._live.map((c) => _liveCard(context, c)),
                    const StudentSectionTitle(title: 'Book live tutoring'),
                    _subscriptionCard(context),
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

  Widget _subscriptionCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppGradients.hero(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: context.accentColor.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🎓', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Pay-Per-Class Plan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Book live one-on-one classes with a tutor. Bundle classes and save more.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            _subLine('1 class — ₦5,000'),
            _subLine('3 classes — ₦14,000 (save ₦1,000)'),
            _subLine('5 classes — ₦22,500 (save ₦2,500)'),
            _subLine('10 classes — ₦43,000 (save ₦7,000)'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const KindBookingScreen(),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Choose package & book',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionScreen(),
                  ),
                ),
                child: Text(
                  'View full plan details',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveCard(BuildContext context, Map<String, dynamic> c) {
    final title = c['title']?.toString() ?? 'Live class';
    final subject = c['subject']?.toString() ?? '';
    final teacher = c['teacher_name']?.toString() ?? 'Teacher';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => joinLiveWithAccessCode(context, _api),
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: KidColors.live.withOpacity(0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: KidColors.live.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFF87171)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.circle,
                        color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [subject, teacher]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: TextStyle(
                            color: context.greyColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: AppGradients.primaryButton,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Join',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
