import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../student/notifications/notifications_screen.dart';
import 'profile/teacher_profile_screen.dart';

/// Shared unread count so every tab's bell stays in sync (IndexedStack keeps screens alive).
final teacherUnreadCount = ValueNotifier<int>(0);

/// Gradient hero header matching student/kid apps.
class TeacherHeroHeader extends StatelessWidget {
  final String greeting;
  final String subtitle;
  final IconData icon;
  final String? badge;

  const TeacherHeroHeader({
    super.key,
    required this.greeting,
    required this.subtitle,
    this.icon = Icons.school_rounded,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
      decoration: BoxDecoration(
        gradient: AppGradients.hero(context),
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
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scholaxia Teacher',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          greeting,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
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
}

class TeacherTopBar extends StatefulWidget {
  final ApiService api;
  final String? teacherName;
  final int unreadCount;
  final ValueChanged<int>? onUnreadChanged;
  final VoidCallback? onProfileTap;

  const TeacherTopBar({
    super.key,
    required this.api,
    this.teacherName,
    this.unreadCount = 0,
    this.onUnreadChanged,
    this.onProfileTap,
  });

  @override
  State<TeacherTopBar> createState() => _TeacherTopBarState();
}

class _TeacherTopBarState extends State<TeacherTopBar> {
  late int _unread;

  @override
  void initState() {
    super.initState();
    _unread = teacherUnreadCount.value > 0
        ? teacherUnreadCount.value
        : widget.unreadCount;
    teacherUnreadCount.addListener(_syncUnread);
  }

  @override
  void dispose() {
    teacherUnreadCount.removeListener(_syncUnread);
    super.dispose();
  }

  void _syncUnread() {
    if (mounted) setState(() => _unread = teacherUnreadCount.value);
  }

  @override
  void didUpdateWidget(TeacherTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unreadCount != widget.unreadCount &&
        widget.unreadCount > teacherUnreadCount.value) {
      teacherUnreadCount.value = widget.unreadCount;
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    final n = await widget.api.unreadNotificationCount();
    teacherUnreadCount.value = n;
    widget.onUnreadChanged?.call(n);
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final initial = (widget.teacherName ?? 'T').trim().isNotEmpty
        ? widget.teacherName!.trim()[0].toUpperCase()
        : 'T';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: accent, size: 18),
            const SizedBox(width: 6),
            Text('Scholaxia',
                style: TextStyle(
                    color: accent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        Row(
          children: [
            GestureDetector(
              onTap: _openNotifications,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.notifications_outlined,
                      color: context.textColor, size: 24),
                  if (_unread > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: widget.onProfileTap ??
                  () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TeacherProfileScreen()),
                      ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: context.surfColor,
                child: Text(initial,
                    style: TextStyle(
                        color: accent, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TeacherUtils {
  static String greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String formatDateTime(dynamic iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, $h:$m $ap';
    } catch (_) {
      return iso.toString();
    }
  }

  static String relativeTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final diff = DateTime.now().difference(DateTime.parse(iso).toLocal());
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return formatDateTime(iso);
    } catch (_) {
      return iso;
    }
  }

  static Color subjectColor(String subject, [BuildContext? context]) {
    final colors = [
      context?.accentColor ?? AppColors.yellow,
      const Color(0xFF6C63FF),
      const Color(0xFF00C896),
      const Color(0xFFFF6B6B),
      const Color(0xFF3B82F6),
    ];
    return colors[subject.hashCode.abs() % colors.length];
  }

  static Future<void> teacherLogout(BuildContext context, ApiService api) async {
    await api.clearTokens();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}
