import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_service.dart';
import '../../theme/app_theme.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ResetPasswordScreen({super.key, this.initialEmail});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _api = ApiService();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _otpSent = false;
  bool _done = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _debugOtp;

  @override
  void initState() {
    super.initState();
    final seed = (widget.initialEmail ?? '').trim();
    if (seed.isNotEmpty) _emailCtrl.text = seed;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _toast('Enter a valid email address.');
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _api.sendEmailOtp(
        email: email,
        purpose: 'reset_password',
      );
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _debugOtp = res['debug_otp']?.toString();
      });
      final msg = res['message']?.toString() ?? 'Reset code sent to your email.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    final email = _emailCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    final pass = _passCtrl.text;
    final conf = _confirmCtrl.text;

    if (otp.isEmpty) {
      _toast('Enter the code from your email.');
      return;
    }
    if (pass.length < 8) {
      _toast('Password must be at least 8 characters.');
      return;
    }
    if (pass != conf) {
      _toast('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      await _api.resetPassword(email: email, otp: otp, newPassword: pass);
      if (!mounted) return;
      setState(() => _done = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. You can log in now.')),
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back_rounded, color: context.textColor),
                style: IconButton.styleFrom(
                  backgroundColor: context.cardColor,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _done ? 'Password reset' : 'Forgot password?',
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _done
                    ? 'Your password was updated. Sign in with the new one.'
                    : _otpSent
                        ? 'Enter the email code and choose a new password.'
                        : 'Enter your account email and we’ll send a reset code.',
                style: TextStyle(color: context.greyColor, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 28),
              if (_done) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
              ] else ...[
                _label('EMAIL'),
                const SizedBox(height: 6),
                _field(
                  controller: _emailCtrl,
                  hint: 'you@example.com',
                  icon: Icons.email_outlined,
                  type: TextInputType.emailAddress,
                  enabled: !_otpSent && !_loading,
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 18),
                  _label('EMAIL CODE'),
                  const SizedBox(height: 6),
                  _field(
                    controller: _otpCtrl,
                    hint: '6-digit code',
                    icon: Icons.mark_email_read_outlined,
                    type: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                  ),
                  if (_debugOtp != null && _debugOtp!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Debug code: $_debugOtp',
                      style: TextStyle(color: context.accentColor, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _label('NEW PASSWORD'),
                  const SizedBox(height: 6),
                  _field(
                    controller: _passCtrl,
                    hint: 'At least 8 characters',
                    icon: Icons.lock_outline,
                    obscure: _obscurePass,
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: context.greyLColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _label('CONFIRM PASSWORD'),
                  const SizedBox(height: 6),
                  _field(
                    controller: _confirmCtrl,
                    hint: 'Re-enter password',
                    icon: Icons.lock_outline,
                    obscure: _obscureConfirm,
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: context.greyLColor,
                        size: 20,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : (_otpSent ? _reset : _sendCode),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _otpSent ? 'Reset Password' : 'Send Reset Code',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _otpSent = false;
                                _otpCtrl.clear();
                                _passCtrl.clear();
                                _confirmCtrl.clear();
                                _debugOtp = null;
                              });
                            },
                      child: Text(
                        'Use a different email',
                        style: TextStyle(color: context.accentColor),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : _sendCode,
                      child: Text(
                        'Resend code',
                        style: TextStyle(color: context.greyColor),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: context.greyColor,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false,
    bool enabled = true,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      enabled: enabled,
      inputFormatters: inputFormatters,
      style: TextStyle(color: context.textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.greyLColor),
        prefixIcon: Icon(icon, color: context.greyLColor, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: context.cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.accentColor, width: 1.4),
        ),
      ),
    );
  }
}
