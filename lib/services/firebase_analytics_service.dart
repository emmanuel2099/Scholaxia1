import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Tracks authentication activity in Firebase Analytics.
///
/// Firebase Analytics supports Android and iOS. Calls are safely ignored on
/// Windows and other unsupported platforms.
class FirebaseAnalyticsService {
  FirebaseAnalyticsService._();

  static final FirebaseAnalyticsService instance = FirebaseAnalyticsService._();

  FirebaseAnalytics? _analytics;
  bool _ready = false;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _analytics = FirebaseAnalytics.instance;
      await _analytics!.setAnalyticsCollectionEnabled(true);
      _ready = true;
    } catch (e) {
      debugPrint('Firebase Analytics init skipped: $e');
    }
  }

  Future<void> logSignUp({required String role, String? userId}) async {
    await init();
    if (!_ready || _analytics == null) return;
    try {
      if (userId != null && userId.isNotEmpty) {
        await _analytics!.setUserId(id: userId);
      }
      await _analytics!.setUserProperty(name: 'account_role', value: role);
      await _analytics!.logSignUp(signUpMethod: 'email_otp');
      await _analytics!.logEvent(
        name: 'account_created',
        parameters: {'role': role},
      );
    } catch (e) {
      debugPrint('Firebase signup analytics failed: $e');
    }
  }

  Future<void> logLogin({required String role, String? userId}) async {
    await init();
    if (!_ready || _analytics == null) return;
    try {
      if (userId != null && userId.isNotEmpty) {
        await _analytics!.setUserId(id: userId);
      }
      await _analytics!.setUserProperty(name: 'account_role', value: role);
      await _analytics!.logLogin(loginMethod: 'email_password');
    } catch (e) {
      debugPrint('Firebase login analytics failed: $e');
    }
  }
}
