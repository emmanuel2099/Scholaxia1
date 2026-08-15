import 'dart:async';
import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/access_code_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import '../../../widgets/app_header_actions.dart';
import '../skills/skills_screen.dart';
import '../classes/classes_screen.dart';
import '../../../utils/live_join_helper.dart';
import '../saved/saved_classes_screen.dart';
import '../notifications/notifications_screen.dart';
import '../cbt/internal_exams_screen.dart';
import '../games/games_screen.dart';
import '../library/library_screen.dart';
import '../cbt/cbt_screen.dart';
import '../marketplace/marketplace_screen.dart';
import '../assignments/assignment_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  StudentProfile? _profile;
  List<Map<String, dynamic>> _recommendations = [];
  List<Map<String, dynamic>> _liveSessions = [];
  List<Map<String, dynamic>> _recentCbt = [];
  bool _loadingFeed = true;
  String? _joiningClassId;
  int _unreadNotifications = 0;
  Timer? _livePollTimer;

  static const _cardColors = [
    Color(0xFF7C3AED),
    Color(0xFF8B5CF6),
    Color(0xFF9333EA),
    Color(0xFFA855F7),
  ];

  @override
  void initState() {
    super.initState();
    AccessCodeService.instance.onCodeReceived = _loadHomeFeed;
    _loadProfile();
    _loadHomeFeed();
    _loadNotificationBadge();
    _livePollTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _loadHomeFeed(),
    );
  }

  @override
  void dispose() {
    _livePollTimer?.cancel();
    if (AccessCodeService.instance.onCodeReceived == _loadHomeFeed) {
      AccessCodeService.instance.onCodeReceived = null;
    }
    super.dispose();
  }

  Future<void> _loadNotificationBadge() async {
    final count = await _api.unreadNotificationCount();
    if (mounted) setState(() => _unreadNotifications = count);
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _api.getStudentProfile().timeout(
        const Duration(seconds: 12),
      );
      if (mounted) {
        setState(() => _profile = p);
        _loadHomeFeed();
      }
    } catch (_) {}
  }

  Future<T?> _safeCall<T>(Future<T> call) async {
    try {
      return await call.timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _toMaps(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> _dedupeSessions(
    List<Map<String, dynamic>> sessions,
  ) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final s in sessions) {
      final id = _field(s, ['id', 'class_id', 'uuid', 'live_class_id']);
      final key = id.isNotEmpty ? id : s.toString();
      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  Future<void> _loadHomeFeed() async {
    if (mounted) setState(() => _loadingFeed = true);

    try {
      final results = await Future.wait([
        _safeCall(_api.getRecommendationsFeed()),
        _safeCall(_api.listLiveClasses(status: 'live')),
        _safeCall(_api.myAccessCodes()),
        _safeCall(_api.cbtMySessions()),
      ]);

      final recsDirect = results[0] as List<dynamic>?;
      final liveRaw = results[1] as List<dynamic>?;
      final accessData = results[2] as Map<String, dynamic>?;
      final cbtRaw = results[3] as List<dynamic>?;

      final recs = recsDirect ?? <dynamic>[];

      // Join codes keyed by class id (only for currently live classes).
      final codeByClass = <String, String>{};
      if (accessData != null) {
        final codes = (accessData['codes'] as List?) ?? [];
        for (final raw in codes) {
          if (raw is! Map) continue;
          final c = Map<String, dynamic>.from(raw);
          if (c['is_class_live'] == false || c['is_used'] == true) continue;
          final classId = c['class_id']?.toString() ?? '';
          final joinCode = c['join_code']?.toString() ?? '';
          if (classId.isNotEmpty && joinCode.isNotEmpty) {
            codeByClass[classId] = joinCode;
          }
        }
      }

      // Only classes the teacher has actually started (is_live = true).
      final liveNow = _toMaps(liveRaw ?? [])
          .where((s) => s['is_live'] == true)
          .map((s) {
            final copy = Map<String, dynamic>.from(s);
            final id = _field(copy, ['id', 'class_id']);
            final code = codeByClass[id];
            if (code != null && code.isNotEmpty) {
              copy['join_code'] = code;
            }
            return copy;
          })
          .toList();

      final cbtRecent = _toMaps(cbtRaw ?? []).take(5).toList();

      if (mounted) {
        setState(() {
          _recommendations = _toMaps(recs);
          _liveSessions = _dedupeSessions(liveNow);
          _recentCbt = cbtRecent;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingFeed = false);
    }
  }

  bool _isLiveSession(Map<String, dynamic> m) {
    if (m['is_live'] == true) return true;
    return _field(m, ['status'], '').toLowerCase() == 'live';
  }

  String _field(
    Map<String, dynamic> m,
    List<String> keys, [
    String fallback = '',
  ]) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty)
        return v.toString().trim();
    }
    return fallback;
  }

  double _progress(Map<String, dynamic> m) {
    final raw =
        m['progress'] ??
        m['progress_percent'] ??
        m['completion'] ??
        m['percent_complete'];
    if (raw is num)
      return raw > 1
          ? (raw / 100).clamp(0.0, 1.0)
          : raw.toDouble().clamp(0.0, 1.0);
    if (raw is String) {
      final n = double.tryParse(raw.replaceAll('%', '').trim());
      if (n != null)
        return n > 1 ? (n / 100).clamp(0.0, 1.0) : n.clamp(0.0, 1.0);
    }
    return 0;
  }

  String _formatSessionTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $ampm';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _joinSession(Map<String, dynamic> session) async {
    final classId = _field(session, [
      'id',
      'class_id',
      'uuid',
      'live_class_id',
    ]);
    setState(() => _joiningClassId = classId.isNotEmpty ? classId : 'join');
    try {
      final code = _field(session, ['join_code']);
      await joinLiveWithAccessCode(
        context,
        _api,
        initialCode: code.isNotEmpty ? code : null,
      );
    } finally {
      if (mounted) setState(() => _joiningClassId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.fullName.split(' ').first ?? 'Student';
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: context.accentColor,
          onRefresh: _loadHomeFeed,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, name),
                _statsRow(context),
                const SizedBox(height: 8),
                StudentBannerSlider(
                  slides: [
                    StudentBannerSlide(
                      title: 'Ask Sia anything',
                      subtitle:
                          'Your 24/7 AI tutor for JAMB, WAEC & NECO — get instant explanations.',
                      buttonLabel: 'Coming soon',
                      icon: Icons.auto_awesome_rounded,
                      badge: '✨ AI POWERED',
                      onTap: null,
                    ),
                    StudentBannerSlide(
                      title: 'Join Scholaxia Intellect League',
                      subtitle:
                          'Compete live, earn coins, climb national rankings — represent your school.',
                      buttonLabel: 'Coming soon',
                      icon: Icons.emoji_events_rounded,
                      badge: '🏆 LEAGUE',
                      colors: const [
                        Color(0xFF4C1D95),
                        Color(0xFF7C3AED),
                        Color(0xFFC026D3),
                      ],
                      onTap: null,
                    ),
                    StudentBannerSlide(
                      title: 'Friday National Challenge is Live',
                      subtitle:
                          'Nationwide academic championship — play now and climb the ranks.',
                      buttonLabel: 'Coming soon',
                      icon: Icons.flag_rounded,
                      badge: '🔴 LIVE',
                      colors: const [
                        Color(0xFF5B21B6),
                        Color(0xFF7C3AED),
                        Color(0xFF2563EB),
                      ],
                      onTap: null,
                    ),
                    StudentBannerSlide(
                      title: 'Buy Scholaxia Coins',
                      subtitle:
                          'Fuel AI Challenges, Student bets, Class & School battles.',
                      buttonLabel: 'Coming soon',
                      icon: Icons.monetization_on_rounded,
                      badge: '💰 COINS',
                      colors: const [
                        Color(0xFF6D28D9),
                        Color(0xFF7C3AED),
                        Color(0xFFF59E0B),
                      ],
                      onTap: null,
                    ),
                  ],
                ),
                _recommended(context),
                _quickAccess(context),
                _recentPerformance(context),
                _todaySessions(context),
                const SizedBox(height: 110),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext ctx, String name) {
    final exam = _profile?.examType ?? 'JAMB';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
      decoration: BoxDecoration(
        gradient: AppGradients.hero(ctx),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scholaxia',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Hello, $name 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppHeaderActions(
                    lightOnGradient: true,
                    onChanged: _loadNotificationBadge,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.emoji_events_outlined,
                      color: Color(0xFFFBBF24),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$exam prep mode',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Ready to level up today?',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsRow(BuildContext context) {
    final liveCount = '${_liveSessions.length}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: SizedBox(
        height: 110,
        child: Row(
          children: [
            const StudentStatCard(
              icon: Icons.local_fire_department_rounded,
              value: '7',
              label: 'Day streak',
              gradient: [Color(0xFF7C3AED), Color(0xFF9333EA)],
            ),
            const SizedBox(width: 10),
            const StudentStatCard(
              icon: Icons.quiz_rounded,
              value: '84%',
              label: 'CBT avg',
              gradient: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
            const SizedBox(width: 10),
            StudentStatCard(
              icon: Icons.videocam_rounded,
              value: liveCount,
              label: 'Live today',
              gradient: const [Color(0xFFA855F7), Color(0xFFD946EF)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recommended(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudentSectionTitle(
          title: 'Recommended for You',
          action: 'Refresh',
          onAction: _loadHomeFeed,
        ),
        SizedBox(
          height: 188,
          child: _loadingFeed
              ? Center(
                  child: CircularProgressIndicator(color: context.accentColor),
                )
              : _recommendations.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          color: context.accentColor,
                          size: 36,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Complete a CBT or chat with Sia to unlock personalized picks.',
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
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: _recommendations.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) {
                    final item = _recommendations[i];
                    final subject = _field(item, [
                      'subject',
                      'category',
                    ], 'Study');
                    final title = _field(item, [
                      'title',
                      'topic',
                      'name',
                    ], 'Recommended lesson');
                    final duration = _field(item, [
                      'duration',
                      'estimated_time',
                      'time',
                    ], '—');
                    final progress = _progress(item);
                    final color = _cardColors[i % _cardColors.length];
                    return _courseCard(
                      context,
                      subject,
                      title,
                      duration,
                      progress,
                      color,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _courseCard(
    BuildContext context,
    String subject,
    String title,
    String duration,
    double progress,
    Color color,
  ) {
    return Container(
      width: 176,
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(context.isDark ? 0.12 : 0.1),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(19),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    subject.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: context.greyColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          duration,
                          style: TextStyle(
                            color: context.greyColor,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      backgroundColor: color.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    progress > 0
                        ? '${(progress * 100).toInt()}% complete'
                        : 'Not started',
                    style: TextStyle(
                      color: context.greyColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAccess(BuildContext ctx) {
    final items = [
      (
        Icons.assignment_rounded,
        'Internal Exam',
        'Download & take teacher-set exams.',
        const [Color(0xFF7C3AED), Color(0xFF9333EA)],
        const InternalExamsScreen(),
      ),
      (
        Icons.assignment_turned_in_rounded,
        'Assignments',
        'Open teacher PDFs, submit work & see scores.',
        const [Color(0xFF16A34A), Color(0xFF22C55E)],
        const AssignmentScreen(),
      ),
      (
        Icons.workspace_premium_rounded,
        'Skills Training',
        'Learn an income-earning skill.',
        const [Color(0xFF6366F1), Color(0xFF818CF8)],
        const SkillsScreen(),
      ),
      (
        Icons.videocam_rounded,
        'Live Classes',
        'Learn with expert tutors.',
        const [Color(0xFFA855F7), Color(0xFFD946EF)],
        const ClassesScreen(),
      ),
      (
        Icons.video_library_rounded,
        'Saved Classes',
        'Replay your saved lessons.',
        const [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
        const SavedClassesScreen(),
      ),
      (
        Icons.menu_book_rounded,
        'Library',
        'Read study books & materials.',
        const [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
        const LibraryScreen(),
      ),
      (
        Icons.quiz_rounded,
        'Past Questions',
        'Take JAMB, WAEC & NECO as timed CBT.',
        const [Color(0xFF7C3AED), Color(0xFFA78BFA)],
        const CbtScreen(asPastQuestions: true),
      ),
      (
        Icons.sports_esports_rounded,
        'Games',
        'Brain breaks and learning games.',
        const [Color(0xFFEC4899), Color(0xFFF472B6)],
        const GamesScreen(),
      ),
      (
        Icons.storefront_rounded,
        'Marketplace',
        'Gadgets, laptops, phones & more.',
        const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
        const MarketplaceScreen(),
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
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => a.$5),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _recentPerformance(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudentSectionTitle(
          title: 'Recent Performance',
          action: _recentCbt.isEmpty ? 'CBT' : 'Your exams',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: context.isDark
                    ? [const Color(0xFF1A1428), const Color(0xFF221A35)]
                    : [Colors.white, const Color(0xFFF3EEFF)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: context.borderColor),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _recentCbt.isEmpty
                ? Text(
                    'Complete a CBT practice exam to see your real scores here.',
                    style: TextStyle(
                      color: context.greyColor,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < _recentCbt.length; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Divider(
                              height: 1,
                              color: context.borderColor,
                            ),
                          ),
                        _perfFromSession(context, _recentCbt[i], i),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _perfFromSession(
    BuildContext context,
    Map<String, dynamic> s,
    int index,
  ) {
    final title = (s['exam_title']?.toString().trim().isNotEmpty == true)
        ? s['exam_title'].toString()
        : (s['subject']?.toString() ?? 'CBT Exam');
    final pct = (s['percentage'] as num?)?.round() ?? 0;
    final correct = (s['total_correct'] as num?)?.toInt();
    final wrong = (s['total_wrong'] as num?)?.toInt();
    final total = (correct != null && wrong != null) ? correct + wrong : null;
    final scoreLabel = total != null ? '$correct/$total' : '$pct%';
    String tag;
    Color color;
    if (pct >= 70) {
      tag = 'Excellent';
      color = const Color(0xFF7C3AED);
    } else if (pct >= 50) {
      tag = 'Improving';
      color = const Color(0xFF6366F1);
    } else {
      tag = 'Keep going';
      color = const Color(0xFFF59E0B);
    }
    // Alternate accent for visual variety
    if (index % 2 == 1 && pct >= 50) {
      color = const Color(0xFF6366F1);
    }
    return _perfRow(context, title, scoreLabel, tag, color, pctOverride: pct);
  }

  Widget _perfRow(
    BuildContext context,
    String title,
    String score,
    String tag,
    Color color, {
    int? pctOverride,
  }) {
    final pct = pctOverride ?? int.tryParse(score.split('/').first) ?? 0;
    return Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                strokeWidth: 4,
                backgroundColor: color.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
              Text(
                '$pct',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                score,
                style: TextStyle(color: context.greyColor, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.15), color.withOpacity(0.08)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tag == 'Excellent'
                    ? Icons.trending_up_rounded
                    : Icons.show_chart_rounded,
                color: color,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                tag,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _todaySessions(BuildContext ctx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StudentSectionTitle(title: 'Today\'s Live Sessions'),
        if (_loadingFeed)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: ctx.accentColor),
            ),
          )
        else if (_liveSessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: ctx.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ctx.borderColor),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.videocam_off_outlined,
                    color: ctx.greyColor,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No live sessions right now',
                    style: TextStyle(
                      color: ctx.textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Check back later or browse Live Classes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ctx.greyColor, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ..._liveSessions.map((s) {
            final classId = _field(s, [
              'id',
              'class_id',
              'uuid',
              'live_class_id',
            ]);
            final title = _field(s, ['title', 'topic', 'name'], 'Live Session');
            final teacher = _field(s, [
              'teacher_name',
              'teacher',
              'instructor',
              'host',
            ], 'Tutor');
            final time = _formatSessionTime(
              _field(s, ['start_time', 'scheduled_at', 'preferred_time']),
            );
            final isLive = _isLiveSession(s);
            final joining = _joiningClassId == classId;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ctx.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isLive
                        ? const Color(0xFFEF4444).withOpacity(0.4)
                        : ctx.borderColor,
                    width: isLive ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (isLive
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF7C3AED))
                              .withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isLive
                              ? [
                                  const Color(0xFFEF4444),
                                  const Color(0xFFF97316),
                                ]
                              : [
                                  const Color(0xFF7C3AED),
                                  const Color(0xFFA855F7),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isLive ? Icons.sensors_rounded : Icons.person_outline,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isLive)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFEF4444,
                                ).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '● LIVE NOW',
                                style: TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          Text(
                            title,
                            style: TextStyle(
                              color: ctx.textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            time.isNotEmpty ? '$teacher • $time' : teacher,
                            style: TextStyle(
                              color: ctx.greyColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: joining ? null : () => _joinSession(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: isLive
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFEF4444),
                                    Color(0xFFF97316),
                                  ],
                                )
                              : AppGradients.primaryButton,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C3AED).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: joining
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isLive ? 'Join Live' : 'Reserve',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
