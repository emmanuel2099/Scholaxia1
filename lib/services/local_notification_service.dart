import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_service.dart';

/// Polls for new notifications and shows local alerts when the app is backgrounded.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final Set<String> _knownIds = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  Future<void> seedKnownNotifications(ApiService api) async {
    try {
      final items = await api.notifications();
      for (final n in items) {
        if (n is Map) {
          final id = n['id']?.toString();
          if (id != null) _knownIds.add(id);
        }
      }
    } catch (_) {}
  }

  Future<void> _show(String title, String body, String id) async {
    const android = AndroidNotificationDetails(
      'scholaxia_alerts',
      'Scholaxia Alerts',
      channelDescription: 'Announcements and live class alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    await _plugin.show(
      id.hashCode,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> showAlert(String title, String body, {String? id}) async {
    if (!_initialized) await init();
    final key = id ?? title;
    if (_knownIds.contains(key)) return;
    _knownIds.add(key);
    await _show(title, body, key);
  }

  Future<void> poll(ApiService api, {bool showAlerts = true}) async {
    if (!_initialized) await init();
    try {
      final items = await api.notifications();
      for (final n in items) {
        if (n is! Map) continue;
        final id = n['id']?.toString() ?? '';
        if (id.isEmpty || _knownIds.contains(id)) continue;
        _knownIds.add(id);
        if (!showAlerts || n['is_read'] == true) continue;
        final title = n['title']?.toString() ?? 'Scholaxia';
        final body = n['body']?.toString() ?? '';
        await _show(title, body, id);
      }
    } catch (_) {}
  }
}
