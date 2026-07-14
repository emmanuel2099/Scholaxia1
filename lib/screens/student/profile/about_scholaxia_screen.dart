import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class AboutScholaxiaScreen extends StatelessWidget {
  const AboutScholaxiaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        foregroundColor: context.textColor,
        title: Text(
          'About Scholaxia',
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.borderColor),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: context.accentColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.school_rounded,
                  color: context.isDark ? AppColors.background : Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Scholaxia',
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Version 1.0.0',
                style: TextStyle(color: context.greyColor, fontSize: 13),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Scholaxia is your complete student hub — CBT practice, live classes, teacher exams, skills training, library, marketplace, and a vibrant learning community.',
              style: TextStyle(
                color: context.textColor,
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            _feature(
              context,
              Icons.apps_rounded,
              'Everything you need in one app',
              'Library materials, saved live recordings, Tutor AI, Scholaxia Marketplace, and CBT practice for your board.',
            ),
            _feature(
              context,
              Icons.flag_outlined,
              'Built for real students, real results',
              'Prepare for UTME, Junior WAEC, WAEC, NECO, live lessons, and skills — Scholaxia keeps you focused.',
            ),
            _feature(
              context,
              Icons.smart_toy_outlined,
              'Sia AI Tutor',
              'Get instant explanations and answers tailored to your exam subjects.',
            ),
            _feature(
              context,
              Icons.quiz_outlined,
              'CBT Practice',
              'Download subject packs by year and practise offline when you are ready.',
            ),
            _feature(
              context,
              Icons.videocam_outlined,
              'Live Classes',
              'Join real-time sessions with teachers and classmates.',
            ),
            _feature(
              context,
              Icons.groups_outlined,
              'Community',
              'Share ideas, ask questions, and read teacher announcements.',
            ),
            const SizedBox(height: 24),
            Text(
              'Start free, grow at your pace. Create your account, set up your exam profile, pick your subjects, and explore live classes, CBT and skills whenever you are ready.',
              style: TextStyle(color: context.greyColor, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feature(BuildContext context, IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: context.accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(color: context.greyColor, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
