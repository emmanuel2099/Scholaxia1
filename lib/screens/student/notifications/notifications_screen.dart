import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = ApiService();
  List<dynamic> _notifications = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.notifications();
      await _api.markAllNotificationsRead();
      if (mounted) {
        setState(() {
          _notifications = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        foregroundColor: context.textColor,
        title: Text('Notifications',
            style: TextStyle(
                color: context.textColor, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.borderColor),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.accentColor))
          : _error != null
              ? _buildError(context)
              : _notifications.isEmpty
                  ? _buildEmpty(context)
                  : _buildList(context),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline, color: context.greyColor, size: 48),
        const SizedBox(height: 12),
        Text('Could not load notifications',
            style: TextStyle(color: context.textColor, fontSize: 15)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _load,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.accentColor,
            foregroundColor: context.isDark ? AppColors.background : Colors.white,
          ),
          child: const Text('Retry'),
        ),
      ]),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.notifications_off_outlined, color: context.greyColor, size: 56),
        const SizedBox(height: 12),
        Text('No notifications yet',
            style: TextStyle(
                color: context.textColor, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text("You're all caught up!",
            style: TextStyle(color: context.greyColor, fontSize: 13)),
      ]),
    );
  }

  Widget _buildList(BuildContext context) {
    return RefreshIndicator(
      color: context.accentColor,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final n = _notifications[i] as Map<String, dynamic>;
          final isRead = n['is_read'] as bool? ?? true;
          final title = n['title'] as String? ?? 'Notification';
          final message = n['body'] as String? ?? n['message'] as String? ?? '';
          final createdAt = n['created_at'] as String? ?? '';

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isRead
                  ? context.cardColor
                  : context.accentColor.withOpacity(context.isDark ? 0.12 : 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isRead
                    ? context.borderColor
                    : context.accentColor.withOpacity(0.3),
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isRead
                      ? Icons.notifications_outlined
                      : Icons.notifications_active_outlined,
                  color: context.accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(title,
                          style: TextStyle(
                              color: context.textColor,
                              fontSize: 14,
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.bold))),
                  if (!isRead)
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: context.accentColor, shape: BoxShape.circle)),
                ]),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(message,
                      style: TextStyle(
                          color: context.greyColor, fontSize: 13, height: 1.4)),
                ],
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_formatDate(createdAt),
                      style: TextStyle(color: context.greyColor, fontSize: 11)),
                ],
              ])),
            ]),
          );
        },
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
