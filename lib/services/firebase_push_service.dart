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
class FirebasePushService {
  FirebasePushService._();
  static final FirebasePushService instance = FirebasePushService._();

  final _messaging = FirebaseMessaging.instance;
  bool _ready = false;
  String? _lastToken;

  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((_) {
        refreshCommunityBadge(ApiService());
      });

      _messaging.onTokenRefresh.listen((token) => _registerToken(token));

      _ready = true;
    } catch (e) {
      debugPrint('Firebase init skipped: $e');
    }
  }

  Future<void> registerAfterLogin() async {
    if (kIsWeb || !_ready) return;
    try {
      final token = await _messaging.getToken();
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

  void _onForegroundMessage(RemoteMessage message) {
    final title =
        message.notification?.title ?? message.data['title'] ?? 'Scholaxia';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    LocalNotificationService.instance.showAlert(
      title,
      body,
      id: message.messageId,
    );
    refreshCommunityBadge(ApiService());
  }
}
