import 'package:flutter/foundation.dart';
import '../api/api_service.dart';

/// Unread community / announcement notifications for the student bottom nav badge.
final communityUnreadCount = ValueNotifier<int>(0);

Future<void> refreshCommunityBadge(ApiService api) async {
  try {
    final items = await api.notifications();
    final count = items.where((n) {
      if (n is! Map || n['is_read'] == true) return false;
      final t = (n['type']?.toString() ?? '').toLowerCase();
      return t.contains('announcement') ||
          t.contains('community') ||
          t.contains('mention');
    }).length;
    communityUnreadCount.value = count;
  } catch (_) {}
}

Future<void> clearCommunityBadge(ApiService api) async {
  communityUnreadCount.value = 0;
  try {
    final items = await api.notifications();
    final hasUnread = items.any((n) {
      if (n is! Map || n['is_read'] == true) return false;
      final t = (n['type']?.toString() ?? '').toLowerCase();
      return t.contains('announcement') ||
          t.contains('community') ||
          t.contains('mention');
    });
    if (hasUnread) await api.markAllNotificationsRead();
  } catch (_) {}
}

bool isCommentPost(Map<String, dynamic> post) {
  final content = post['content']?.toString() ?? '';
  return content.startsWith('@post:');
}
