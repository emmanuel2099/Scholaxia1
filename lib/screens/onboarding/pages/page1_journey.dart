import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class OnboardingPage1 extends StatelessWidget {
  const OnboardingPage1({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            children: [
              Container(
                height: 320,
                width: double.infinity,
                color: Theme.of(context).cardColor,
                child: Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.yellow.withOpacity(0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.yellow.withOpacity(0.15),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Container(
                        color: const Color(0xFF071A0F),
                        child: const Icon(
                          Icons.person,
                          size: 130,
                          color: AppColors.yellow,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 20,
                right: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.surfColor,
                    borderRadius: BorderRadius.circular(22),
                    border:
                        Border.all(color: AppColors.yellow.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, color: AppColors.yellow, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'AI Powered',
                        style: TextStyle(
                          color: AppColors.yellow,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                      Icon(Icons.verified, color: AppColors.yellow, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Premium Content',
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
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'PREMIUM LEARNING',
                  style: TextStyle(
                    color: AppColors.yellow,
                    fontSize: 12,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
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
                        text: 'Your Journey\nto ',
                        style: TextStyle(color: context.textColor),
                      ),
                      TextSpan(
                        text: 'Excellence',
                        style: TextStyle(color: AppColors.yellow),
                      ),
                      TextSpan(
                        text: '\nStarts Here.',
                        style: TextStyle(color: context.textColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Experience a new era of AI-driven education. Scholaxia combines academic rigor with futuristic intelligence to illuminate your path to success.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.greyLColor,
                    fontSize: 15,
                    height: 1.6,
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
