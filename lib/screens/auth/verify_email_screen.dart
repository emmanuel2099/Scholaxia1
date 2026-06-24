import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../student/student_shell.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());
  bool _isVerifying = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitEntered(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  bool get _isComplete =>
      _controllers.every((c) => c.text.isNotEmpty);

  void _verify() async {
    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const StudentShell()),
        (_) => false,
      );
    }
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
              const SizedBox(height: 40),
              // Animated icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.yellow.withOpacity(0.3), width: 2),
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    color: AppColors.yellow, size: 40),
              ),
              const SizedBox(height: 24),
              const Text(
                'Verify Your Email',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                      color: AppColors.greyLight,
                      fontSize: 14,
                      height: 1.5),
                  children: [
                    TextSpan(text: "We sent a 6-digit code to\n"),
                    TextSpan(
                      text: 'name@university.edu',
                      style: TextStyle(
                          color: AppColors.yellow,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // OTP input
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _buildOtpBox(i)),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isComplete && !_isVerifying ? _verify : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellow,
                    disabledBackgroundColor:
                        AppColors.yellow.withOpacity(0.4),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Verify & Continue →',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Didn't receive the code? ",
                    style: TextStyle(
                        color: AppColors.greyLight, fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: const Text(
                      'Resend',
                      style: TextStyle(
                        color: AppColors.yellow,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final isFilled = _controllers[index].text.isNotEmpty;
    return SizedBox(
      width: 46,
      height: 56,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: isFilled
              ? AppColors.yellow.withOpacity(0.12)
              : AppColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isFilled ? AppColors.yellow : const Color(0xFF3A3A3A),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isFilled ? AppColors.yellow : const Color(0xFF3A3A3A),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.yellow, width: 2),
          ),
        ),
        onChanged: (v) => _onDigitEntered(index, v),
      ),
    );
  }
}
