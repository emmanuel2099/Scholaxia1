import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'widgets/auth_text_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: AppColors.white, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset,
                    color: AppColors.yellow, size: 36),
              ),
              const SizedBox(height: 24),
              const Text(
                'Reset Password',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Enter your email and we'll send you\na link to reset your password.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.greyLight,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),
              if (!_sent) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FieldLabel(text: 'EMAIL ADDRESS'),
                      const SizedBox(height: 8),
                      AuthTextField(
                        controller: _emailController,
                        hint: 'name@university.edu',
                        prefixIcon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () =>
                              setState(() => _sent = true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.yellow,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Send Reset Link →',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2010),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF1A5C2A).withOpacity(0.6)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.mark_email_read_outlined,
                          color: Color(0xFF4ADE80), size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Check your inbox!',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We sent a password reset link to your email. Check your spam folder if you don\'t see it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.greyLight,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: () => setState(() => _sent = false),
                        child: const Text(
                          'Resend email',
                          style: TextStyle(
                            color: AppColors.yellow,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.white,
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back to Login'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.grey,
        fontSize: 11,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
