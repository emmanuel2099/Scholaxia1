import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../widgets/feature_card.dart';

class OnboardingPage2 extends StatelessWidget {
  const OnboardingPage2({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 300,
            width: double.infinity,
            color: Theme.of(context).cardColor,
            child: Center(
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0xFF003320), Color(0xFF050F0A)],
                    radius: 0.8,
                  ),
                ),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  size: 130,
                  color: AppColors.yellow,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                      Icon(Icons.auto_awesome,
                          color: AppColors.yellow, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'AI-POWERED LEARNING',
                        style: TextStyle(
                          color: AppColors.yellow,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    children: [
                      TextSpan(
                          text: 'Meet ',
                          style: TextStyle(color: context.textColor)),
                      TextSpan(
                          text: 'Sia',
                          style: TextStyle(color: AppColors.yellow)),
                      TextSpan(
                          text: ', Your AI Tutor',
                          style: TextStyle(color: context.textColor)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Get instant answers, personalized lesson plans, and 24/7 support. Education designed around you.',
                  style: TextStyle(
                    color: context.greyLColor,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                const FeatureCard(
                  icon: Icons.flash_on,
                  title: 'Instant Answers',
                  subtitle: 'No more waiting for feedback.',
                ),
                const SizedBox(height: 12),
                const FeatureCard(
                  icon: Icons.trending_up,
                  title: 'Smart Plans',
                  subtitle: 'Customized to your curriculum.',
                ),
                const SizedBox(height: 12),
                const FeatureCard(
                  icon: Icons.access_time,
                  title: '24/7 Access',
                  subtitle: 'Study whenever inspiration strikes.',
                ),
                const SizedBox(height: 160),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
