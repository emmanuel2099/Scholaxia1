import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash/splash_screen.dart';
import 'services/app_update_service.dart';
import 'services/firebase_analytics_service.dart';
import 'services/firebase_push_service.dart';
import 'services/local_notification_service.dart';
import 'services/offline_status_service.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };

  // Paint the splash immediately; defer heavy plugin init so release builds
  // don't sit on the white Android launch screen if a plugin fails.
  runApp(const ScholaxiaApp());
  unawaited(_bootstrap());
}

Future<void> _bootstrap() async {
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

class ScholaxiaApp extends StatefulWidget {
  const ScholaxiaApp({super.key});

  @override
  State<ScholaxiaApp> createState() => _ScholaxiaAppState();
}

class _ScholaxiaAppState extends State<ScholaxiaApp> {
  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(_onThemeChanged);
    // Give the first screen a moment to mount, then check for a newer build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        AppUpdateService.instance.checkForUpdate(appNavigatorKey);
      });
    });
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scholaxia',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeNotifier.mode,
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
      home: const SplashScreen(),
    );
  }
}
