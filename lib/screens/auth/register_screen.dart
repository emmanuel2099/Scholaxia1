import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../teacher/teacher_shell.dart';
import 'exam_subject_setup_screen.dart';
import 'login_screen.dart';
import 'role_select_screen.dart';

class RegisterScreen extends StatefulWidget {
  final AccountRole? accountRole;

  const RegisterScreen({super.key, this.accountRole});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  final _api = ApiService();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    final conf  = _confirmCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all required fields.')));
      return;
    }
    if (pass != conf) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passwords do not match.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = await _api.studentSignup(
          email: email, password: pass, fullName: name);
      if (!mounted) return;
      if (auth.role == 'teacher') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const TeacherShell()),
          (_) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ExamSubjectSetupScreen()),
          (_) => false,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().toLowerCase();
      final message = err.contains('failed to fetch') || err.contains('clientexception')
          ? 'Could not reach scholaxia1.onrender.com. The server may be waking up — wait 30 seconds and try again.'
          : 'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final btnFg = context.isDark ? AppColors.background : Colors.white;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Create Account',
            style: TextStyle(
                color: context.textColor,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.textColor),
                children: [
                  const TextSpan(text: 'Welcome to '),
                  TextSpan(
                      text: 'Scholaxia',
                      style: TextStyle(color: context.accentColor)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create an account to start your personalized\nlearning journey with Sia AI.',
              style: TextStyle(
                  fontSize: 13, color: context.greyColor, height: 1.5),
            ),
            const SizedBox(height: 28),
            _label(context, 'Full Name'),
            const SizedBox(height: 6),
            _field(context, ctrl: _nameCtrl, hint: 'John Doe', icon: Icons.person_outline),
            const SizedBox(height: 16),
            _label(context, 'Email Address'),
            const SizedBox(height: 6),
            _field(
                context,
                ctrl: _emailCtrl,
                hint: 'john@example.com',
                icon: Icons.mail_outline,
                type: TextInputType.emailAddress),
            const SizedBox(height: 16),
            _label(context, 'Password'),
            const SizedBox(height: 6),
            _field(
              context,
              ctrl: _passCtrl,
              hint: '••••••••',
              icon: Icons.security_outlined,
              obscure: _obscurePass,
              suffix: GestureDetector(
                onTap: () => setState(() => _obscurePass = !_obscurePass),
                child: Icon(
                  _obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: context.greyLColor,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label(context, 'Confirm Password'),
            const SizedBox(height: 6),
            _field(
              context,
              ctrl: _confirmCtrl,
              hint: '••••••••',
              icon: Icons.lock_outline,
              obscure: _obscureConfirm,
              suffix: GestureDetector(
                onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
                child: Icon(
                  _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: context.greyLColor,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: btnFg,
                  disabledBackgroundColor: context.greyColor.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: btnFg))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Create Account',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: btnFg)),
                          const SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18, color: btnFg),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account? ',
                      style: TextStyle(color: context.greyColor, fontSize: 13)),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LoginScreen(
                          accountRole:
                              widget.accountRole ?? AccountRole.student,
                        ),
                      ),
                    ),
                    child: Text('Log In',
                        style: TextStyle(
                            color: context.accentColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                "By creating an account, you agree to Scholaxia's Terms of Service and Privacy Policy.",
                textAlign: TextAlign.center,
                style: TextStyle(color: context.greyLColor, fontSize: 11, height: 1.5),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String t) => Text(t,
      style: TextStyle(
          color: context.textColor,
          fontSize: 13,
          fontWeight: FontWeight.w600));

  Widget _field(
    BuildContext context, {
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: context.surfColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
        ),
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          obscureText: obscure,
          style: TextStyle(color: context.textColor, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.greyLColor),
            prefixIcon: Icon(icon, color: context.greyLColor, size: 20),
            suffixIcon: suffix,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      );
}
