import 'package:flutter/material.dart';

import 'vendor_login_screen.dart';
import 'vendor_onboarding_screen.dart';
import 'vendor_shell.dart';
import '../../api/api_service.dart';
import '../../services/app_prefs.dart';
import 'vendor_theme.dart';

class VendorSplashScreen extends StatefulWidget {
  const VendorSplashScreen({super.key});

  @override
  State<VendorSplashScreen> createState() => _VendorSplashScreenState();
}

class _VendorSplashScreenState extends State<VendorSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
    _boot();
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted || _navigated) return;

    final api = ApiService();
    final hasSession = await api.hasValidSession();
    final role = ((await api.getRole()) ?? '').toLowerCase().trim();

    if (hasSession && role == 'vendor') {
      _go(const VendorShell());
      return;
    }

    if (hasSession && role.isNotEmpty && role != 'vendor') {
      await api.clearTokens();
    }

    final prefs = await AppPrefs.instance();
    final seen = prefs.getBool('vendor_onboarding_seen') ?? false;
    _go(seen ? const VendorLoginScreen() : const VendorOnboardingScreen());
  }

  void _go(Widget dest) {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => dest,
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 420),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [VendorTheme.maroon, VendorTheme.maroonDark, Color(0xFF1F1218)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.storefront_rounded, size: 44, color: Colors.white),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Market Vendor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Requests · Approvals · Sales',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
