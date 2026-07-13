import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Terms for Scholaxia Kids + pay-per-class bookings.
class KindTermsScreen extends StatelessWidget {
  const KindTermsScreen({super.key});

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
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'By using Scholaxia Kids and booking live classes, you and your parent/guardian agree to the following:',
            style: TextStyle(
              color: context.textColor,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _section(context, 'Pay-per-class packages', [
            'Payment must be confirmed before a class or bundle is fully scheduled.',
            'You may reschedule with at least 24 hours notice.',
            'Missed classes without prior notice count as used.',
            'Bundled classes are valid for 90 days from the booking date.',
            'Each class is 90 minutes of one-on-one tutoring.',
          ]),
          _section(context, 'Kids app use', [
            'Scholaxia Kids is designed for young learners with parent/guardian oversight.',
            'Keep login details private and use the app for learning only.',
            'Do not share personal information with strangers in chats or groups.',
            'We may remove content or accounts that break these rules.',
          ]),
          _section(context, 'Support', [
            'For billing or booking help, contact support@scholaxia.com.',
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        color: context.greyLColor,
                        fontSize: 13,
                        height: 1.4,
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
