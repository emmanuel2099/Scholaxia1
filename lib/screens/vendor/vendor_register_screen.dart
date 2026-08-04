import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import '../../services/firebase_analytics_service.dart';
import '../../services/firebase_push_service.dart';
import '../../theme/app_theme.dart';
import 'vendor_login_screen.dart';
import 'vendor_shell.dart';

class VendorRegisterScreen extends StatefulWidget {
  const VendorRegisterScreen({super.key});

  @override
  State<VendorRegisterScreen> createState() => _VendorRegisterScreenState();
}

class _VendorRegisterScreenState extends State<VendorRegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _categoriesCtrl = TextEditingController();
  final _api = ApiService();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _otpStep = false;
  String _pendingEmail = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _otpCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _addressCtrl.dispose();
    _businessNameCtrl.dispose();
    _categoriesCtrl.dispose();
    super.dispose();
  }

  List<String> _csv(String raw) => raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _sendOtp() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final conf = _confirmCtrl.text;
    final business = _businessNameCtrl.text.trim();
    final location = _locationCtrl.text.trim();
    final address = _addressCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || pass.isEmpty || business.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill name, email, password and business name.')),
      );
      return;
    }
    if (location.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location and address are required.')),
      );
      return;
    }
    if (pass.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters.')),
      );
      return;
    }
    if (pass != conf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await _api.signupStart(
        email: email,
        password: pass,
        fullName: name,
        role: 'vendor',
        phone: _phoneCtrl.text.trim(),
        location: location,
        address: address,
        businessName: business,
        categories: _csv(_categoriesCtrl.text),
      );
      if (!mounted) return;
      setState(() {
        _otpStep = true;
        _pendingEmail = result['email']?.toString() ?? email;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP sent. Check your email and spam folder.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the OTP sent to your email.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = await _api.signupVerify(email: _pendingEmail, otp: otp);
      if (auth.role.toLowerCase() != 'vendor') {
        await _api.clearTokens();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created but it is not a vendor account.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await FirebaseAnalyticsService.instance.logSignUp(
        role: auth.role,
        userId: auth.userId,
      );
      await FirebasePushService.instance.registerAfterLogin();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VendorShell()),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: Text(_otpStep ? 'Verify Email' : 'Create Vendor Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_otpStep) {
              setState(() => _otpStep = false);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _otpStep ? 'Enter email code' : 'Start selling on Scholaxia',
              style: TextStyle(
                color: context.textColor,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _otpStep
                  ? 'We sent a code to $_pendingEmail'
                  : 'Create your vendor store account with business details.',
              style: TextStyle(color: context.greyColor),
            ),
            const SizedBox(height: 22),
            if (!_otpStep) ...[
              _label('Full Name'),
              _field(_nameCtrl, 'Your name', Icons.person_outline),
              _label('Business Name'),
              _field(_businessNameCtrl, 'My Shop', Icons.storefront_outlined),
              _label('Email'),
              _field(_emailCtrl, 'vendor@example.com', Icons.email_outlined, type: TextInputType.emailAddress),
              _label('Phone'),
              _field(_phoneCtrl, '+234...', Icons.phone_outlined, type: TextInputType.phone),
              _label('Location'),
              _field(_locationCtrl, 'City / State', Icons.location_on_outlined),
              _label('Address'),
              _field(_addressCtrl, 'Street address', Icons.home_outlined),
              _label('Categories (comma separated)'),
              _field(_categoriesCtrl, 'books, gadgets', Icons.category_outlined),
              _label('Password'),
              _field(
                _passCtrl,
                '••••••••',
                Icons.lock_outline,
                obscure: _obscurePass,
                suffix: IconButton(
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  icon: Icon(_obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              _label('Confirm Password'),
              _field(
                _confirmCtrl,
                '••••••••',
                Icons.lock_outline,
                obscure: _obscureConfirm,
                suffix: IconButton(
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ] else ...[
              _label('Email OTP'),
              _field(_otpCtrl, '6-digit code', Icons.mark_email_read_outlined, type: TextInputType.number),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : (_otpStep ? _verifyOtp : _sendOtp),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_otpStep ? 'Verify & Create Store' : 'Send Email Code'),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const VendorLoginScreen()),
                  );
                },
                child: const Text('Already have an account? Log In'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 10),
        child: Text(
          text,
          style: TextStyle(color: context.textColor, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType type = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    // Force light fill + dark text so dark theme cannot hide typed text.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        obscureText: obscure,
        cursorColor: AppColors.primary,
        style: const TextStyle(
          color: Color(0xFF1F2937),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          prefixIcon: Icon(icon, color: const Color(0xFF6B7280), size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: context.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: context.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}
