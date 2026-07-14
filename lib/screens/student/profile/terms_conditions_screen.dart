import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// Student Terms & Conditions (mirrors desktop About / policies).
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        foregroundColor: context.textColor,
        title: Text(
          'Terms & Conditions',
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'By using Scholaxia you agree to these terms. Please read them carefully.',
            style: TextStyle(
              color: context.textColor,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _section(context, 'Using Scholaxia', [
            'Scholaxia is a student learning hub for CBT practice, live classes, Sia AI, library, marketplace, and community.',
            'Keep your login details private. You are responsible for activity on your account.',
            'Use the app for learning only — no spam, scams, or harassment.',
          ]),
          _section(context, 'Community & Groups', [
            'Do not share phone numbers, WhatsApp links, external links, or abusive language.',
            'If the system detects prohibited content, you may be removed from a group or Community automatically.',
            'Teachers and admins may remove posts or members who break the rules.',
          ]),
          _section(context, 'CBT & live classes', [
            'Practice CBT packs can be downloaded for offline use after you pick a subject and year.',
            'School exams and live-class rules set by your teacher still apply online and offline.',
            'Do not share exam answers or disrupt live sessions.',
          ]),
          _section(context, 'Marketplace', [
            'Products are listed by Scholaxia admin. Booking requests are for contacting you — payment and delivery are arranged with Scholaxia.',
            'Provide accurate name, WhatsApp, phone, and email when booking.',
          ]),
          _section(context, 'Support', [
            'Questions? Email support@scholaxia.com. We reply within 1–2 school days.',
            'Scholaxia may update these terms; continued use means you accept the latest version.',
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<String> bullets) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.textColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: context.accentColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        color: context.greyColor,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
