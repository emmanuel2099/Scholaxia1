import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash/splash_screen.dart';
import 'services/firebase_push_service.dart';
import 'services/local_notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeNotifier.load();
  await LocalNotificationService.instance.init();
  await FirebasePushService.instance.init();
  runApp(const ScholaxiaApp());
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
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeNotifier.mode,
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor:
              brightness == Brightness.dark ? AppColors.surface : Colors.white,
          systemNavigationBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ));
        return child ?? const SizedBox.shrink();
      },
      home: const SplashScreen(),
    );
  }
}
