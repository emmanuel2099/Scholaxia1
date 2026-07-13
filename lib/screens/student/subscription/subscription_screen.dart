import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  static const _plans = [
    _Plan(
      classes: 1,
      price: '₦5,000',
      savings: null,
      subtitle: '90 minutes',
    ),
    _Plan(
      classes: 3,
      price: '₦14,000',
      savings: 'Save ₦1,000',
      subtitle: '90 minutes each',
    ),
    _Plan(
      classes: 5,
      price: '₦22,500',
      savings: 'Save ₦2,500',
      subtitle: '90 minutes each',
    ),
    _Plan(
      classes: 10,
      price: '₦43,000',
      savings: 'Save ₦7,000',
      subtitle: '90 minutes each',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Text(
                    'Subscribe',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: AppGradients.hero(context),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎓',
                      style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  const Text(
                    'Scholaxia Pay-Per-Class Plan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bundle & save on live one-on-one tutoring.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const StudentSectionTitle(title: 'Choose a bundle'),
            ..._plans.map((p) => _planCard(context, p)),
            const StudentSectionTitle(title: "What's included"),
            _bulletList(context, const [
              'Live one-on-one class',
              "Any subject of the student's choice",
              'Experienced tutor',
              'Class notes and learning materials',
              'Questions & answers during the session',
              'Assignment (if applicable)',
            ]),
            const StudentSectionTitle(title: 'Terms & conditions'),
            _bulletList(context, const [
              'Payment must be made before each class or bundle is confirmed.',
              'Students may reschedule with at least 24 hours notice.',
              'Missed classes without prior notice are considered used.',
              'Bundled classes are valid for 90 days from the date of purchase.',
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Payment coming soon — contact Scholaxia support to subscribe.',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Subscribe now',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(BuildContext context, _Plan plan) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${plan.classes} Class${plan.classes == 1 ? '' : 'es'}',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    plan.subtitle,
                    style: TextStyle(color: context.greyColor, fontSize: 12),
                  ),
                  if (plan.savings != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      plan.savings!,
                      style: TextStyle(
                        color: const Color(0xFF22C55E),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              plan.price,
              style: TextStyle(
                color: context.accentColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bulletList(BuildContext context, List<String> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        children: items
            .map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: context.accentColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t,
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Plan {
  final int classes;
  final String price;
  final String? savings;
  final String subtitle;

  const _Plan({
    required this.classes,
    required this.price,
    required this.savings,
    required this.subtitle,
  });
}
