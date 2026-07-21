import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_face_verify_screen.dart';
import 'sil_models.dart';
import 'sil_onboarding.dart';
import 'sil_shell.dart';
import 'sil_widgets.dart';

/// League entry for an **already logged-in student**.
/// Never opens student Login / Signup — only League setup or play.
class SilEntryScreen extends StatefulWidget {
  const SilEntryScreen({super.key});

  @override
  State<SilEntryScreen> createState() => _SilEntryScreenState();
}

class _SilEntryScreenState extends State<SilEntryScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _statusText = 'Opening Intellect League…';
    });

    // Must already be a signed-in student (came from Home).
    final token = await _api.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in as a Student first, then open the League.'),
        ),
      );
      Navigator.pop(context);
      return;
    }

    try {
      final status = await _api.silStatus();
      if (!mounted) return;
      if (status['enrolled'] == true) {
        final profile = SilProfile.fromJson(status);
        await _enterLeague(profile, offline: false);
        return;
      }
    } catch (_) {
      // API may not have SIL deployed yet — use local enrollment if any.
    }

    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString('sil_local_profile');
    if (local != null && mounted) {
      final profile =
          SilProfile.fromJson(jsonDecode(local) as Map<String, dynamic>);
      await _enterLeague(profile, offline: true);
      return;
    }

    // Not enrolled yet → League profile setup (NOT student account signup).
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SilOnboardingScreen()),
    );
  }

  Future<void> _enterLeague(SilProfile profile, {required bool offline}) async {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _statusText = 'Face check…';
    });

    await _api.setAppResumeMode('league');

    final selfie = await SilFaceVerifyScreen.open(
      context,
      title: 'Verify to enter League',
      subtitle:
          'Quick face check before you play. You are already signed in as a student.',
      requireApi: !offline,
    );
    if (!mounted) return;
    if (selfie == null) {
      await _api.setAppResumeMode('student');
      Navigator.pop(context); // back to Home — stay logged in
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sil_last_face_ok', DateTime.now().toIso8601String());
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
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Intellect League',
          style: TextStyle(
              color: context.textColor, fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: SilColors.purple),
            const SizedBox(height: 16),
            Text(
              _statusText ?? 'Loading…',
              style: TextStyle(color: context.greyColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Your student account stays signed in.',
              style: TextStyle(color: context.greyColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
