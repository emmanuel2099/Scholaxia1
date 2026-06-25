import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../kind/kind_shared.dart';
import '../kind/kind_shell.dart';
import 'login_screen.dart';
import 'role_select_screen.dart';

class KidRegisterScreen extends StatefulWidget {
  const KidRegisterScreen({super.key});

  @override
  State<KidRegisterScreen> createState() => _KidRegisterScreenState();
}

class _KidRegisterScreenState extends State<KidRegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _parentEmailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String _ageGroup = '6-8';
  final _api = ApiService();

  static const _ageGroups = ['3-5', '6-8', '9-12'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _parentEmailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final conf = _confirmCtrl.text;
    final parentEmail = _parentEmailCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields.')),
      );
      return;
    }
    if (pass != conf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }
    if (pass.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _api.kindSignup(
        email: email,
        password: pass,
        fullName: name,
        ageGroup: _ageGroup,
        parentEmail: parentEmail.isEmpty ? null : parentEmail,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const KindShell()),
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
          content: Text('Something went wrong. Please try again.'),
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
      appBar: AppBar(
        backgroundColor: context.headerColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Kid Sign Up',
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
            Text(
              'Create a kid learner account',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: context.textColor),
            ),
            const SizedBox(height: 8),
            Text(
              'For young learners ages 3–12 with kid-safe AI tutoring.',
              style: TextStyle(
                  fontSize: 13, color: context.greyColor, height: 1.5),
            ),
            const SizedBox(height: 28),
            _label(context, "Child's Name"),
            const SizedBox(height: 6),
            _field(context,
                ctrl: _nameCtrl, hint: 'Amina', icon: Icons.child_care_outlined),
            const SizedBox(height: 16),
            _label(context, 'Age Group'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.surfColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _ageGroup,
                  isExpanded: true,
                  dropdownColor: context.cardColor,
                  style: TextStyle(color: context.textColor, fontSize: 15),
                  items: _ageGroups
                      .map((g) => DropdownMenuItem(
                            value: g,
                            child: Text('Ages $g'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _ageGroup = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label(context, 'Email Address'),
            const SizedBox(height: 6),
            _field(
              context,
              ctrl: _emailCtrl,
              hint: 'parent@example.com',
              icon: Icons.mail_outline,
              type: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _label(context, 'Parent Email (optional)'),
            const SizedBox(height: 6),
            _field(
              context,
              ctrl: _parentEmailCtrl,
              hint: 'parent@example.com',
              icon: Icons.family_restroom_outlined,
              type: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _label(context, 'Password'),
            const SizedBox(height: 6),
            _field(
              context,
              ctrl: _passCtrl,
              hint: '••••••••',
              icon: Icons.lock_outline,
              obscure: _obscurePass,
              suffix: GestureDetector(
                onTap: () => setState(() => _obscurePass = !_obscurePass),
                child: Icon(
                  _obscurePass
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
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
                  _obscureConfirm
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
              child: ElevatedButton(
                onPressed: _loading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KidColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: context.greyColor.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Create Account',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
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
                        builder: (_) =>
                            LoginScreen(accountRole: AccountRole.kind),
                      ),
                    ),
                    child: Text('Log In',
                        style: TextStyle(
                            color: KidColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
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
