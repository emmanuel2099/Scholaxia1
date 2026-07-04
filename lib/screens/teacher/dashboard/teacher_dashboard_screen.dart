import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import '../cbt/teacher_cbt_screen.dart';
import '../teacher_shared.dart';

class TeacherDashboardScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigate;

  const TeacherDashboardScreen({super.key, this.onNavigate});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _loadError;
  String _teacherName = 'Teacher';
  int _unread = 0;
  int _liveCount = 0;
  int _upcomingCount = 0;
  int _pendingGrading = 0;
  int _groupCount = 0;
  List<Map<String, dynamic>> _todayClasses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getTeacherMe(),
        _api.unreadNotificationCount(),
        _api.listLiveClasses(status: 'live'),
        _api.listLiveClasses(status: 'upcoming'),
        _api.teacherPendingAssignments(),
        _api.listSchoolGroups(),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final live = (results[2] as List).cast<dynamic>();
      final upcoming = (results[3] as List).cast<dynamic>();
      final pending = results[4] as List;
      final groups = results[5] as List;

      final today = DateTime.now();
      final schedule = <Map<String, dynamic>>[];
      for (final raw in [...live, ...upcoming]) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final start = m['start_time']?.toString();
        if (start == null) continue;
        try {
          final dt = DateTime.parse(start).toLocal();
          if (dt.year == today.year &&
              dt.month == today.month &&
              dt.day == today.day) {
            schedule.add(m);
          }
        } catch (_) {
          schedule.add(m);
        }
      }

      if (mounted) {
        setState(() {
          _teacherName = profile['full_name']?.toString() ?? 'Teacher';
          _unread = results[1] as int;
          _liveCount = live.length;
          _upcomingCount = upcoming.length;
          _pendingGrading = pending.length;
          _groupCount = groups.length;
          _todayClasses = schedule;
          _loading = false;
        });
        teacherUnreadCount.value = results[1] as int;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              e is ApiException ? e.message : 'Could not load dashboard.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _teacherName.split(' ').first;
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
                            child: TeacherTopBar(
                              api: _api,
                              teacherName: _teacherName,
                              unreadCount: _unread,
                            ),
                          ),
                          TeacherHeroHeader(
                            greeting: '${TeacherUtils.greeting()}, $firstName!',
                            subtitle:
                                '$_liveCount live · $_upcomingCount upcoming · $_pendingGrading to grade',
                            badge: _liveCount > 0 ? '$_liveCount LIVE' : null,
                          ),
                          if (_loadError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.3)),
                                ),
                                child: Text(_loadError!,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 12)),
                              ),
                            ),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                  icon: Icons.event_rounded,
                                  value: '$_upcomingCount',
                                  label: 'Upcoming',
                                  gradient: const [
                                    Color(0xFF6366F1),
                                    Color(0xFF818CF8),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                StudentStatCard(
                                  icon: Icons.groups_rounded,
                                  value: '$_groupCount',
                                  label: 'Groups',
                                  gradient: const [
                                    Color(0xFF7C3AED),
                                    Color(0xFF9333EA),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          StudentFeatureBanner(
                            title: 'Host a live class',
                            subtitle:
                                'Go live from your phone — video, board, screen share, and chat.',
                            buttonLabel: 'Open Classes',
                            icon: Icons.videocam_rounded,
                            onTap: () => widget.onNavigate?.call(1),
                          ),
                          _quickAccess(context),
                          const StudentSectionTitle(title: "Today's Schedule"),
                          if (_todayClasses.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'No classes scheduled for today.',
                                style: TextStyle(color: context.greyColor),
                              ),
                            )
                          else
                            ..._todayClasses
                                .map((c) => _scheduleItem(context, c)),
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
        Icons.school_rounded,
        'Classes',
        'Host or schedule live lessons.',
        const [Color(0xFFA855F7), Color(0xFFD946EF)],
        () => widget.onNavigate?.call(1),
      ),
      (
        Icons.groups_rounded,
        'Groups',
        'Create school study groups.',
        const [Color(0xFF6366F1), Color(0xFF818CF8)],
        () => widget.onNavigate?.call(2),
      ),
      (
        Icons.people_rounded,
        'Community',
        'Announcements & student chat.',
        const [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
        () => widget.onNavigate?.call(3),
      ),
      (
        Icons.grading_rounded,
        'Grading',
        'Score student submissions.',
        const [Color(0xFFEF4444), Color(0xFFF87171)],
        () => widget.onNavigate?.call(4),
      ),
      (
        Icons.quiz_rounded,
        'Exams',
        'Create Scholaxia exams.',
        const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeacherCbtScreen()),
        ),
      ),
      (
        Icons.auto_awesome_rounded,
        'Sia AI',
        'Lesson plans & quiz ideas.',
        const [Color(0xFF7C3AED), Color(0xFF9333EA)],
        () => widget.onNavigate?.call(5),
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

  Widget _scheduleItem(BuildContext context, Map<String, dynamic> c) {
    final subject =
        c['subject']?.toString() ?? c['title']?.toString() ?? 'Class';
    final isLive = c['is_live'] == true;
    final color = TeacherUtils.subjectColor(subject, context);
    final time = TeacherUtils.formatDateTime(c['start_time']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isLive ? color.withOpacity(0.4) : context.borderColor,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.7)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isLive ? Icons.videocam_rounded : Icons.event_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    time,
                    style: TextStyle(color: context.greyColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (isLive ? color : context.greyColor).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isLive ? 'Live' : 'Upcoming',
                style: TextStyle(
                  color: isLive ? color : context.greyColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
