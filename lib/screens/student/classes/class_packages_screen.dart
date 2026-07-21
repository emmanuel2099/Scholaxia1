import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../services/paystack_checkout_service.dart';
import '../../../services/support_contact_service.dart';
import '../../../theme/app_theme.dart';

class ClassPackagesScreen extends StatelessWidget {
  const ClassPackagesScreen({super.key, this.kidsOnly = false});

  final bool kidsOnly;

  /// Exact Scholaxia packages from product pricing.
  static const _kidSections = [
    _PackageSection(
      title: 'One-on-One Classes',
      plans: [
        _ClassPackage(
          id: 'nursery_standard',
          name: 'Nursery One-on-One Classes',
          price: 50000,
          billing: '₦50,000 / Month',
          features: [
            'Reading',
            'Phonics',
            'Counting',
            'Fun games',
            'Learning activities',
            'Parent feedback session',
          ],
        ),
        _ClassPackage(
          id: 'primary_standard',
          name: 'Primary School One-on-One Classes',
          price: 55000,
          billing: '₦55,000 / Monthly',
          features: [
            'Mathematics',
            'Phonics',
            'English language',
            'Moral values',
            'Homework',
            'Parent feedback session',
            'Progress report',
          ],
        ),
      ],
    ),
    _PackageSection(
      title: 'Holiday Classes',
      plans: [
        _ClassPackage(
          id: 'holiday_primary',
          name: 'Primary Holiday Classes',
          price: 15000,
          billing: '₦15,000',
          features: [
            'Mathematics',
            'English language',
            'Phonics',
            'Moral values',
          ],
        ),
      ],
    ),
  ];

  static const _studentSections = [
    _PackageSection(
      title: 'One-on-One Classes',
      plans: [
        _ClassPackage(
          id: 'secondary_standard',
          name: 'High School (JSS & SSS) One-on-One Classes',
          price: 50000,
          billing: '₦50,000',
          features: [
            '3 subjects of choice',
            'One-on-one with tutor',
            'Topic-based assessments',
            'Performance analytics',
            'Unlimited Sia AI Tutor',
          ],
        ),
      ],
    ),
    _PackageSection(
      title: 'Scholaxia Holiday Promo Classes',
      plans: [
        _ClassPackage(
          id: 'holiday_ss_science',
          name: 'Senior Secondary SS 1–3 · Science',
          price: 11000,
          billing: '₦11,000 · 5 classes weekly',
          features: [
            'Mathematics',
            'English',
            'Physics',
            'Chemistry',
            'Biology',
          ],
        ),
        _ClassPackage(
          id: 'holiday_ss_art',
          name: 'Senior Secondary SS 1–3 · Art',
          price: 11000,
          billing: '₦11,000 · 5 classes weekly',
          features: [
            'Mathematics',
            'English',
            'Lit. In English',
            'CRS/IRS',
            'Government',
          ],
        ),
        _ClassPackage(
          id: 'holiday_ss_commercial',
          name: 'Senior Secondary SS 1–3 · Commercial',
          price: 11000,
          billing: '₦11,000 · 5 classes weekly',
          features: [
            'Mathematics',
            'English',
            'F. Accounting',
            'Commerce',
            'Economics',
          ],
        ),
        _ClassPackage(
          id: 'holiday_jss',
          name: 'Junior Secondary / JSS 1–3',
          price: 10500,
          billing: '₦10,500 · 5 classes weekly',
          features: [
            'Mathematics',
            'English Language',
            'Phonics',
            'French',
            'Computer',
          ],
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final sections = kidsOnly ? _kidSections : _studentSections;
    final total = sections.fold<int>(0, (sum, s) => sum + s.plans.length);

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: Text(kidsOnly ? 'Kids class packages' : 'Class packages'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            kidsOnly
                ? 'Nursery & Primary packages'
                : 'Secondary & Holiday packages',
            style: TextStyle(
              color: context.textColor,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            kidsOnly
                ? '$total packages for Nursery and Primary learners.'
                : '$total packages — scroll to see every High School and Holiday option.',
            style: TextStyle(color: context.greyColor),
          ),
          const SizedBox(height: 18),
          for (final section in sections) ...[
            Text(
              section.title,
              style: TextStyle(
                color: context.textColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...section.plans.map((plan) => _PackageCard(plan: plan)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.plan});

  final _ClassPackage plan;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.name,
              style: TextStyle(
                color: context.textColor,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              plan.billing,
              style: TextStyle(
                color: context.accentColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...plan.features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF22C55E),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(feature)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _buy(context),
                child: Text('Pay ${plan.billing.split('·').first.trim()}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _buy(BuildContext context) async {
    try {
      final paid = await PaystackCheckoutService.purchase(
        context: context,
        api: ApiService(),
        productType: 'class_package',
        productId: plan.id,
      );
      if (!context.mounted || !paid) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmed. Your class package is active.'),
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      final message = e.message;
      final paystackMissing = message.toLowerCase().contains('paystack') &&
          message.toLowerCase().contains('not configured');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paystackMissing
                ? 'Paystack keys are missing on the server. Chat WhatsApp to enroll meanwhile.'
                : message,
          ),
          backgroundColor: Colors.red,
          action: paystackMissing
              ? SnackBarAction(
                  label: 'WhatsApp',
                  textColor: Colors.white,
                  onPressed: SupportContactService.openWhatsApp,
                )
              : null,
        ),
      );
    }
  }
}

class _PackageSection {
  const _PackageSection({required this.title, required this.plans});

  final String title;
  final List<_ClassPackage> plans;
}

class _ClassPackage {
  const _ClassPackage({
    required this.id,
    required this.name,
    required this.price,
    required this.billing,
    required this.features,
  });

  final String id;
  final String name;
  final int price;
  final String billing;
  final List<String> features;
}
