import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_face_verify_screen.dart';
import 'sil_models.dart';
import 'sil_shell.dart';
import 'sil_widgets.dart';
import 'sil_onboarding.dart';

/// Entry: enrollment check → face verify every time you enter League → shell.
class SilEntryScreen extends StatefulWidget {
  const SilEntryScreen({super.key});

  @override
  State<SilEntryScreen> createState() => _SilEntryScreenState();
}

class _SilEntryScreenState extends State<SilEntryScreen> {
  final _api = ApiService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _loading = true);
    try {
      final status = await _api.silStatus();
      if (!mounted) return;
      if (status['enrolled'] == true) {
        final profile = SilProfile.fromJson(status);
        await _gateWithFace(profile, offline: false);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('sil_local_profile');
      if (local != null) {
        final profile =
            SilProfile.fromJson(jsonDecode(local) as Map<String, dynamic>);
        if (!mounted) return;
        await _gateWithFace(profile, offline: true);
        return;
      }
      setState(() => _loading = false);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('sil_local_profile');
      if (local != null && mounted) {
        final profile =
            SilProfile.fromJson(jsonDecode(local) as Map<String, dynamic>);
        await _gateWithFace(profile, offline: true);
        return;
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _gateWithFace(SilProfile profile, {required bool offline}) async {
    if (!mounted) return;
    setState(() => _loading = false);
    final selfie = await SilFaceVerifyScreen.open(
      context,
      title: 'Verify to enter League',
      subtitle:
          'Face verification is required every time you open Scholaxia Intellect League.',
      requireApi: !offline,
    );
    if (!mounted) return;
    if (selfie == null) {
      Navigator.pop(context);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sil_last_face_ok',
      DateTime.now().toIso8601String(),
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SilShell(profile: profile, offline: offline),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.bgColor,
        body: const Center(
          child: CircularProgressIndicator(color: SilColors.purple),
        ),
      );
    }
    return const SilWelcomeScreen();
  }
}

class SilWelcomeScreen extends StatelessWidget {
  const SilWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const Spacer(),
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [SilColors.purpleDeep, SilColors.purple],
                  ),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: Colors.white, size: 80),
              ),
              const SizedBox(height: 28),
              const Text(
                'Challenge Your Mind,\nWin Every Time!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                  color: Color(0xFF1F1635),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Join Scholaxia Intellect League — compete live, earn coins, and represent your school.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              SilPrimaryButton(
                label: "Let's Play  →",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SilOnboardingScreen()),
                  );
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Skip for now',
                    style: TextStyle(color: Colors.grey.shade600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
