import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_service.dart';
import 'community_badge.dart';
import 'local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Registers FCM device token with Scholaxia API for real push notifications.
/// Android/iOS only — skipped on Windows/desktop/web.
class FirebasePushService {
  FirebasePushService._();

  static final FirebasePushService instance = FirebasePushService._();

  FirebaseMessaging? _messaging;
  bool _ready = false;
  Future<void>? _initializing;
  String? _lastToken;

  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (!_supported || _ready) return;
    final currentInitialization = _initializing;
    if (currentInitialization != null) {
      await currentInitialization;
      return;
    }
    final initialization = _initialize();
    _initializing = initialization;
    await initialization;
  }

  Future<void> _initialize() async {
    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

      _messaging!.onTokenRefresh.listen((token) => _registerToken(token));

      _ready = true;
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        await _handleOpenedMessage(initialMessage);
      }
    } catch (e) {
      debugPrint('Firebase init skipped: $e');
    } finally {
      _initializing = null;
    }
  }

  Future<void> registerAfterLogin() async {
    await init();
    if (!_ready || _messaging == null) return;
    try {
      final token = await _messaging!.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    if (token.isEmpty || token == _lastToken) return;
    final api = ApiService();
    if (!await api.hasValidSession()) return;
    try {
      await api.registerDeviceToken(
        token: token,
        platform: Platform.isAndroid
            ? 'android'
            : Platform.isIOS
                ? 'ios'
                : 'web',
      );
      _lastToken = token;
    } catch (e) {
      debugPrint('Device token API failed: $e');
    }
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    try {
      final data = <String, String>{};
      for (final entry in message.data.entries) {
        final key = entry.key.trim();
        if (key.isNotEmpty && entry.value != null) {
          data[key] = entry.value.toString();
        }
      }
      debugPrint(
        'Opened FCM notification'
        '${message.messageId == null ? '' : ' ${message.messageId}'}'
        '${data.isEmpty ? '' : ' (${data.keys.join(', ')})'}',
      );
      await refreshCommunityBadge(ApiService());
    } catch (e) {
      debugPrint('FCM notification payload ignored: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'Scholaxia';
    final body =
        message.notification?.body ?? message.data['body']?.toString() ?? '';
    LocalNotificationService.instance.showAlert(
      title,
      body,
      id: message.messageId,
    );
    refreshCommunityBadge(ApiService());
  }
}
