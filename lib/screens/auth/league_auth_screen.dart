import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import '../../services/firebase_push_service.dart';
import '../../theme/app_theme.dart';
import '../student/sil/sil_widgets.dart';
import '../student/student_shell.dart';
import 'role_select_screen.dart';

/// Dedicated Intellect League auth — not the Student app login screen.
class LeagueAuthScreen extends StatefulWidget {
  const LeagueAuthScreen({super.key});

  @override
  State<LeagueAuthScreen> createState() => _LeagueAuthScreenState();
}

class _LeagueAuthScreenState extends State<LeagueAuthScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final name = _nameCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty || (_signUp && name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in all fields to continue.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      if (_signUp) {
        final auth = await _api.studentSignup(
          email: email,
          password: pass,
          fullName: name,
        );
        if (auth.role != 'student') {
          await _api.clearTokens();
          throw ApiException(400, 'League needs a student account.');
        }
      } else {
        final auth = await _api.login(email: email, password: pass);
        if (auth.role != 'student') {
          await _api.clearTokens();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Use a student email/password for Intellect League.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      try {
        FirebasePushService.instance.registerAfterLogin();
      } catch (_) {}
      await _api.setAppResumeMode('league');
      // League login / signup → open Intellect League (not study dashboard alone).
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const StudentShell(openSilOnStart: true),
        ),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not reach the server. Try again shortly.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4C1D95), Color(0xFF7C3AED)],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RoleSelectScreen()),
                          );
                        },
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.emoji_events_rounded,
                        color: Color(0xFFFBBF24), size: 56),
                    const SizedBox(height: 12),
                    const Text(
                      'Scholaxia Intellect League',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _signUp
                          ? 'Create your League access (same as a student account).'
                          : 'Sign in to compete, earn coins, and represent your school.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _signUp ? 'Create League account' : 'League sign in',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Not the Student study dashboard login — this opens Intellect League.',
                      style: TextStyle(
                          color: context.greyColor, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 20),
                    if (_signUp) ...[
                      TextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: _dec(context, 'Full name'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _dec(context, 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: _dec(context, 'Password').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SilPrimaryButton(
                      label: _signUp ? 'Create & enter League' : 'Enter League',
                      loading: _loading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() => _signUp = !_signUp),
                      child: Text(
                        _signUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create League account',
                        style: const TextStyle(
                          color: SilColors.purple,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RoleSelectScreen()),
                        );
                      },
                      child: Text(
                        'Back to role select',
                        style: TextStyle(color: context.greyColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: SilColors.purpleSoft.withOpacity(0.35),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SilColors.purple, width: 1.5),
      ),
    );
  }
}
