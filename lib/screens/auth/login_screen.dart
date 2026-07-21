import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../services/firebase_analytics_service.dart';
import '../../services/firebase_push_service.dart';
import '../../theme/app_theme.dart';
import '../kind/kind_shell.dart';
import '../student/student_shell.dart';
import '../teacher/teacher_shell.dart';
import 'kid_register_screen.dart';
import 'register_screen.dart';
import 'role_select_screen.dart';

class LoginScreen extends StatefulWidget {
  final AccountRole? accountRole;

  const LoginScreen({super.key, this.accountRole});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  final _api = ApiService();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = await _api.login(email: email, password: pass);
      if (!mounted) return;

      final role = auth.role.toLowerCase().trim();

      if (!_roleMatches(role)) {
        await _api.clearTokens();
        if (!mounted) return;
        final expected = _expectedRoleLabel();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'That account is not a $expected account. Pick the correct type on the previous screen.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await FirebaseAnalyticsService.instance.logLogin(
        role: role,
        userId: auth.userId,
      );

      // Always clear stack and land on the correct home.
      Widget home;
      if (role == 'teacher') {
        home = const TeacherShell();
      } else if (role == 'kind') {
        home = const KindShell();
      } else if (widget.accountRole == AccountRole.gameChallenge) {
        // Game Challenge login → Intellect League
        await _api.setAppResumeMode('league');
        home = const StudentShell(openSilOnStart: true);
      } else {
        // Student study login → student dashboard only
        await _api.setAppResumeMode('student');
        home = const StudentShell(openSilOnStart: false);
      }

      await FirebasePushService.instance.registerAfterLogin();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => home),
        (_) => false,
      );

      if (role == 'student') {
        // ignore: unawaited_futures
        _api.ensureStudentProfile();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().toLowerCase();
      final message =
          err.contains('failed to fetch') || err.contains('clientexception')
          ? 'Could not reach scholaxia1.onrender.com. The server may be waking up — wait 30 seconds and try again.'
          : 'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _roleMatches(String role) {
    final pick = widget.accountRole;
    if (pick == null) return true;
    switch (pick) {
      case AccountRole.teacher:
        return role == 'teacher';
      case AccountRole.kind:
        return role == 'kind';
      case AccountRole.student:
      case AccountRole.gameChallenge:
        return role == 'student';
    }
  }

  String _expectedRoleLabel() {
    switch (widget.accountRole) {
      case AccountRole.teacher:
        return 'Teacher';
      case AccountRole.kind:
        return 'Kid';
      case AccountRole.gameChallenge:
        return 'Game Challenge (Student)';
      case AccountRole.student:
      case null:
        return 'Student';
    }
  }

  String get _title {
    switch (widget.accountRole) {
      case AccountRole.teacher:
        return 'Teacher Login';
      case AccountRole.kind:
        return 'Kid Login';
      case AccountRole.gameChallenge:
        return 'League Login';
      case AccountRole.student:
      case null:
        return 'Welcome Back';
    }
  }

  String get _subtitle {
    switch (widget.accountRole) {
      case AccountRole.teacher:
        return 'Sign in with the email and password from your school admin.';
      case AccountRole.kind:
        return 'Sign in to your kid learner account.';
      case AccountRole.gameChallenge:
        return 'Sign in with your student account to enter\nScholaxia Intellect League.';
      case AccountRole.student:
      case null:
        return 'Enter your credentials to access your\npersonalized learning dashboard.';
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
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                decoration: BoxDecoration(
                  gradient: AppGradients.hero(context),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.88),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 28),
                    _label(context, 'EMAIL'),
                    const SizedBox(height: 6),
                    _field(
                      context,
                      controller: _emailCtrl,
                      hint: 'you@example.com',
                      icon: Icons.email_outlined,
                      type: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _label(context, 'PASSWORD'),
                        GestureDetector(
                          onTap: () {},
                          child: Text(
                            'Forgot Password?',
                            style: TextStyle(
                              color: context.accentColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _field(
                      context,
                      controller: _passCtrl,
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      suffix: GestureDetector(
                        onTap: () => setState(() => _obscure = !_obscure),
                        child: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: context.greyLColor,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: _loading
                              ? null
                              : AppGradients.primaryButton,
                          borderRadius: BorderRadius.circular(14),
                          color: _loading
                              ? context.greyColor.withOpacity(0.3)
                              : null,
                        ),
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
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
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Log In',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: Divider(color: context.borderColor)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR CONTINUE WITH',
                            style: TextStyle(
                              color: context.greyLColor,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: context.borderColor)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'SECURE AI-POWERED EDUCATION',
                      style: TextStyle(
                        color: context.greyLColor,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RoleSelectScreen(),
                            ),
                          ),
                          child: Text(
                            'Change account type',
                            style: TextStyle(
                              color: context.accentColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.accountRole == null ||
                        widget.accountRole == AccountRole.student ||
                        widget.accountRole == AccountRole.gameChallenge ||
                        widget.accountRole == AccountRole.kind) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account yet? ",
                            style: TextStyle(
                              color: context.greyColor,
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (widget.accountRole == AccountRole.kind) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const KidRegisterScreen(),
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RegisterScreen(
                                      accountRole: widget.accountRole,
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              'Create Account',
                              style: TextStyle(
                                color: context.accentColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: TextStyle(
        color: context.textColor,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) => Container(
    decoration: BoxDecoration(
      color: context.surfColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.borderColor),
    ),
    child: TextField(
      controller: controller,
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
