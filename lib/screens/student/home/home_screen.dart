import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../cbt/cbt_screen.dart';
import '../classes/classes_screen.dart';
import '../classes/live_class_screen.dart';
import '../community/community_screen.dart';
import '../notifications/notifications_screen.dart';
import '../sia/sia_screen.dart';

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
  bool _loadingFeed = true;
  String? _joiningClassId;
  int _unreadNotifications = 0;

  static const _cardColors = [
    Color(0xFF22C55E),
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFFF97316),
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadHomeFeed();
    _loadNotificationBadge();
  }

  Future<void> _loadNotificationBadge() async {
    final count = await _api.unreadNotificationCount();
    if (mounted) setState(() => _unreadNotifications = count);
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _api.getStudentProfile().timeout(const Duration(seconds: 12));
      if (mounted) setState(() => _profile = p);
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

  List<Map<String, dynamic>> _dedupeSessions(List<Map<String, dynamic>> sessions) {
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
      // Use endpoints confirmed on server; /home/feed currently returns 404.
      final results = await Future.wait([
        _safeCall(_api.getRecommendationsFeed()),
        _safeCall(_api.listLiveClasses(status: 'live')),
        _safeCall(_api.listLiveClasses(status: 'upcoming')),
      ]);

      final recsDirect = results[0] as List<dynamic>?;
      final live = results[1] as List<dynamic>?;
      final upcoming = results[2] as List<dynamic>?;

      final recs = recsDirect ?? <dynamic>[];
      final sessions = _dedupeSessions(_toMaps([...?live, ...?upcoming]));

      if (mounted) {
        setState(() {
          _recommendations = _toMaps(recs);
          _liveSessions = sessions;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingFeed = false);
    }
  }

  String _field(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return fallback;
  }

  double _progress(Map<String, dynamic> m) {
    final raw = m['progress'] ?? m['progress_percent'] ?? m['completion'] ?? m['percent_complete'];
    if (raw is num) return raw > 1 ? (raw / 100).clamp(0.0, 1.0) : raw.toDouble().clamp(0.0, 1.0);
    if (raw is String) {
      final n = double.tryParse(raw.replaceAll('%', '').trim());
      if (n != null) return n > 1 ? (n / 100).clamp(0.0, 1.0) : n.clamp(0.0, 1.0);
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
    final classId = _field(session, ['id', 'class_id', 'uuid', 'live_class_id']);
    if (classId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This session is missing a class ID.')),
        );
      }
      return;
    }

    setState(() => _joiningClassId = classId);
    try {
      await _api.joinLiveClass(classId);
      final userId = await _api.getUserId() ?? 'student';
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveClassScreen(
            classId: classId,
            subject: _field(session, ['subject'], 'General'),
            topic: _field(session, ['title', 'topic', 'name'], 'Live Class'),
            userId: userId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Could not join session. Try again.',
            ),
          ),
        );
      }
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
                _recommended(context),
                _quickAccess(context),
                _recentPerformance(context),
                _todaySessions(context),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext ctx, String name) {
    return Container(
      color: ctx.headerColor,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ctx.accentColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.school_rounded,
                color: ctx.isDark ? AppColors.background : Colors.white, size: 20),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () async {
              await Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
              if (mounted) _loadNotificationBadge();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ctx.bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ctx.borderColor),
                  ),
                  child: Icon(Icons.notifications_outlined, color: ctx.textColor, size: 20),
                ),
                if (_unreadNotifications > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: ctx.accentColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ctx.isDark ? AppColors.background : Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommended(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recommended for You',
                  style: TextStyle(
                      color: context.textColor, fontSize: 16, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: _loadHomeFeed,
                child: Text('Refresh',
                    style: TextStyle(
                        color: context.accentColor, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: _loadingFeed
              ? Center(child: CircularProgressIndicator(color: context.accentColor))
              : _recommendations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'No recommendations yet. Complete a CBT or ask Sia to get personalized picks.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.greyColor, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: _recommendations.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final item = _recommendations[i];
                        final subject = _field(item, ['subject', 'category'], 'Study');
                        final title = _field(item, ['title', 'topic', 'name'], 'Recommended lesson');
                        final duration = _field(item, ['duration', 'estimated_time', 'time'], '—');
                        final progress = _progress(item);
                        final color = _cardColors[i % _cardColors.length];
                        return _courseCard(context, subject, title, duration, progress, color);
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
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subject,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(title,
              style: TextStyle(
                  color: context.textColor, fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.access_time, size: 12, color: context.greyColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(duration,
                    style: TextStyle(color: context.greyColor, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text('${(progress * 100).toInt()}% Completed',
              style: TextStyle(color: context.greyColor, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _quickAccess(BuildContext ctx) {
    final items = [
      {
        'icon': Icons.chat_bubble_outline,
        'label': 'Sia AI Tutor',
        'sub': 'Get instant answers to tough questions.',
        'color': const Color(0xFF22C55E),
        'dest': const SiaScreen()
      },
      {
        'icon': Icons.menu_book_outlined,
        'label': 'CBT Practice',
        'sub': 'Timed mock exams for JAMB & WAEC.',
        'color': const Color(0xFF3B82F6),
        'dest': const CbtScreen()
      },
      {
        'icon': Icons.videocam_outlined,
        'label': 'Live Classes',
        'sub': 'Learn in real time with expert tutors.',
        'color': const Color(0xFFF97316),
        'dest': const ClassesScreen()
      },
      {
        'icon': Icons.library_books_outlined,
        'label': 'Library',
        'sub': 'Access thousands of study materials.',
        'color': const Color(0xFF8B5CF6),
        'dest': const CommunityScreen()
      },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text('Quick Access',
              style: TextStyle(color: ctx.textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: items.map((a) {
              final color = a['color'] as Color;
              return GestureDetector(
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => a['dest'] as Widget),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ctx.cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ctx.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(a['icon'] as IconData, color: color, size: 17),
                      ),
                      const SizedBox(height: 6),
                      Text(a['label'] as String,
                          style: TextStyle(
                              color: ctx.textColor, fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(a['sub'] as String,
                          style: TextStyle(color: ctx.greyColor, fontSize: 10, height: 1.25),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Performance',
                  style: TextStyle(
                      color: context.textColor, fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Last 7 Days', style: TextStyle(color: context.greyColor, fontSize: 12)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                _perfRow(context, 'Biology CBT Mock', '84/100', 'Excellent', context.accentColor),
                Divider(height: 20, color: context.borderColor),
                _perfRow(context, 'Use of English Prep', '72/100', 'Improving', const Color(0xFF3B82F6)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _perfRow(BuildContext context, String title, String score, String tag, Color color) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: context.textColor, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(score, style: TextStyle(color: context.greyColor, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tag == 'Excellent' ? Icons.trending_up : Icons.show_chart,
                  color: color, size: 12),
              const SizedBox(width: 4),
              Text(tag,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text('Today Live Sessions',
              style: TextStyle(color: ctx.textColor, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        if (_loadingFeed)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: ctx.accentColor)),
          )
        else if (_liveSessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ctx.cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ctx.borderColor),
              ),
              child: Text(
                'No live or upcoming sessions right now. Check back later or browse Live Classes.',
                style: TextStyle(color: ctx.greyColor, fontSize: 13),
              ),
            ),
          )
        else
          ..._liveSessions.map((s) {
            final classId = _field(s, ['id', 'class_id', 'uuid', 'live_class_id']);
            final title = _field(s, ['title', 'topic', 'name'], 'Live Session');
            final teacher = _field(s, ['teacher_name', 'teacher', 'instructor', 'host'], 'Tutor');
            final time = _formatSessionTime(
              _field(s, ['start_time', 'scheduled_at', 'preferred_time']),
            );
            final status = _field(s, ['status'], 'upcoming').toLowerCase();
            final isLive = status == 'live';
            final joining = _joiningClassId == classId;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ctx.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ctx.borderColor),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: ctx.accentColor.withOpacity(0.12),
                          child: Icon(Icons.person_outline, color: ctx.accentColor, size: 20),
                        ),
                        if (isLive)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  color: ctx.textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text(
                            time.isNotEmpty ? 'with $teacher • $time' : 'with $teacher',
                            style: TextStyle(color: ctx.greyColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: joining ? null : () => _joinSession(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: ctx.accentColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: joining
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ctx.isDark ? AppColors.background : Colors.white,
                                ),
                              )
                            : Text(
                                isLive ? 'Join' : 'Reserve',
                                style: TextStyle(
                                  color: ctx.isDark ? AppColors.background : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
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
