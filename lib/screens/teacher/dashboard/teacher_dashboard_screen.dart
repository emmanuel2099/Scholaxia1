import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../teacher_shared.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

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
  int _materialCount = 0;
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
        _api.teacherMaterials(),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final live = (results[2] as List).cast<dynamic>();
      final upcoming = (results[3] as List).cast<dynamic>();
      final pending = results[4] as List;
      final materials = results[5] as List;

      final today = DateTime.now();
      final schedule = <Map<String, dynamic>>[];
      for (final raw in [...live, ...upcoming]) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final start = m['start_time']?.toString();
        if (start == null) continue;
        try {
          final dt = DateTime.parse(start).toLocal();
          if (dt.year == today.year && dt.month == today.month && dt.day == today.day) {
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
          _materialCount = materials.length;
          _todayClasses = schedule;
          _loading = false;
        });
        teacherUnreadCount.value = results[1] as int;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e is ApiException ? e.message : 'Could not load dashboard.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _teacherName.split(' ').first;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.yellow,
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.yellow))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      TeacherTopBar(
                        api: _api,
                        teacherName: _teacherName,
                        unreadCount: _unread,
                      ),
                      const SizedBox(height: 20),
                      Text('${TeacherUtils.greeting()},',
                          style: const TextStyle(color: AppColors.greyLight, fontSize: 14)),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold),
                          children: [
                            TextSpan(
                                text: firstName,
                                style: const TextStyle(color: AppColors.yellow)),
                          ],
                        ),
                      ),
                      if (_loadError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Text(_loadError!,
                              style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'You have $_liveCount live, $_upcomingCount upcoming classes and $_pendingGrading pending submissions.',
                        style: const TextStyle(color: AppColors.grey, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                              child: _StatCard(
                                  value: '$_liveCount',
                                  label: 'Live Now',
                                  icon: Icons.videocam_outlined,
                                  color: AppColors.yellow)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _StatCard(
                                  value: '$_upcomingCount',
                                  label: 'Upcoming',
                                  icon: Icons.event_outlined,
                                  color: const Color(0xFF6C63FF))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _StatCard(
                                  value: '$_pendingGrading',
                                  label: 'To Grade',
                                  icon: Icons.pending_actions_outlined,
                                  color: const Color(0xFFFF6B6B))),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text("Today's Schedule",
                          style: TextStyle(
                              color: AppColors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (_todayClasses.isEmpty)
                        const Text('No classes scheduled for today.',
                            style: TextStyle(color: AppColors.grey))
                      else
                        ..._todayClasses.map(_scheduleItem),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _scheduleItem(Map<String, dynamic> c) {
    final subject = c['subject']?.toString() ?? c['title']?.toString() ?? 'Class';
    final isLive = c['is_live'] == true;
    final color = TeacherUtils.subjectColor(subject);
    final time = TeacherUtils.formatDateTime(c['start_time']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isLive ? color.withOpacity(0.4) : const Color(0xFF2A2A2A)),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subject,
                      style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(time,
                      style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isLive ? color : AppColors.grey).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isLive ? 'Live' : 'Upcoming',
                style: TextStyle(
                    color: isLive ? color : AppColors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.value,
      required this.label,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}
