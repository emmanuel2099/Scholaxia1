import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../widgets/exam_chip.dart';

class OnboardingPage3 extends StatelessWidget {
  const OnboardingPage3({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            children: [
              Container(
                height: 280,
                width: double.infinity,
                color: Theme.of(context).cardColor,
                child: Center(
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xFF003320), Color(0xFF050F0A)],
                        radius: 0.9,
                      ),
                    ),
                    child: const Icon(
                      Icons.computer,
                      size: 110,
                      color: AppColors.yellow,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.surfColor,
                    borderRadius: BorderRadius.circular(22),
                    border:
                        Border.all(color: AppColors.yellow.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          color: AppColors.yellow, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'JAMB: 320+',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    children: [
                      TextSpan(
                          text: 'Master Your ',
                          style: TextStyle(color: context.textColor)),
                      TextSpan(
                          text: 'Exams.',
                          style: TextStyle(color: AppColors.yellow)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Practice with WAEC, JAMB, and NECO mock tests designed for success. Experience the real CBT environment before the big day.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.greyLColor,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ExamChip(label: 'WAEC'),
                    SizedBox(width: 12),
                    ExamChip(label: 'JAMB'),
                    SizedBox(width: 12),
                    ExamChip(label: 'NECO'),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF071A0F),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, color: AppColors.primary, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Mock Exams',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 180),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
