import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/api_service.dart';
import 'screens/vendor/vendor_splash_screen.dart';
import 'services/app_prefs.dart';
import 'services/firebase_analytics_service.dart';
import 'services/firebase_push_service.dart';
import 'services/local_notification_service.dart';
import 'services/offline_status_service.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> vendorNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };

  runApp(const ScholaxiaVendorApp());
  unawaited(_bootstrap());
}

Future<void> _bootstrap() async {
  try {
    await ensurePrefsHealthy();
  } catch (e, st) {
    debugPrint('Prefs recovery failed: $e\n$st');
  }
  try {
    await themeNotifier.load();
  } catch (e, st) {
    debugPrint('Theme load failed: $e\n$st');
  }
  try {
    await LocalNotificationService.instance.init();
  } catch (e, st) {
    debugPrint('Local notifications init failed: $e\n$st');
  }
  try {
    await FirebasePushService.instance.init();
  } catch (e, st) {
    debugPrint('Firebase init failed: $e\n$st');
  }
  try {
    await FirebaseAnalyticsService.instance.init();
  } catch (e, st) {
    debugPrint('Firebase Analytics init failed: $e\n$st');
  }
}

class ScholaxiaVendorApp extends StatefulWidget {
  const ScholaxiaVendorApp({super.key});

  @override
  State<ScholaxiaVendorApp> createState() => _ScholaxiaVendorAppState();
}

class _ScholaxiaVendorAppState extends State<ScholaxiaVendorApp> {
  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(_onThemeChanged);
    sessionExpiredNotifier.addListener(_onSessionExpired);
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChanged);
    sessionExpiredNotifier.removeListener(_onSessionExpired);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onSessionExpired() {
    final msg = sessionExpiredNotifier.value;
    if (msg == null) return;
    sessionExpiredNotifier.value = null;
    final nav = vendorNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const VendorSplashScreen()),
      (_) => false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = vendorNavigatorKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            msg.toLowerCase().contains('another device')
                ? 'You signed in on another device. Please sign in again.'
                : 'Your session ended. Please sign in again.',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scholaxia Vendor',
      navigatorKey: vendorNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      // Vendor UI is a light maroon system — keep inputs readable.
      themeMode: ThemeMode.light,
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarColor: brightness == Brightness.dark
                ? AppColors.surface
                : Colors.white,
            systemNavigationBarIconBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
          ),
        );
        return OfflineStatusBanner(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const VendorSplashScreen(),
    );
  }
}
