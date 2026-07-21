import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../services/paystack_checkout_service.dart';
import '../../../theme/app_theme.dart';

class ClassPackagesScreen extends StatelessWidget {
  const ClassPackagesScreen({super.key, this.kidsOnly = false});

  final bool kidsOnly;

  static const _kidPlans = [
    _ClassPackage(
      id: 'nursery_standard',
      name: 'Nursery One-on-One',
      price: 50000,
      billing: 'per month',
      features: [
        'Reading',
        'Phonics',
        'Counting',
        'Fun games and learning activities',
        'Parent feedback session',
      ],
    ),
    _ClassPackage(
      id: 'primary_standard',
      name: 'Primary School One-on-One',
      price: 55000,
      billing: 'per month',
      features: [
        'Mathematics',
        'Phonics',
        'English Language',
        'Moral values and homework',
        'Parent feedback and progress report',
      ],
    ),
    _ClassPackage(
      id: 'holiday_primary',
      name: 'Primary Holiday Classes',
      price: 15000,
      billing: 'holiday package',
      features: ['Mathematics', 'English Language', 'Phonics', 'Moral values'],
    ),
  ];

  static const _studentPlans = [
    _ClassPackage(
      id: 'secondary_standard',
      name: 'High School One-on-One (JSS & SSS)',
      price: 50000,
      billing: 'per month',
      features: [
        'Three subjects of choice',
        'One-on-one tutor',
        'Topic-based assessments',
        'Performance analytics',
        'Unlimited Sia AI Tutor',
      ],
    ),
    _ClassPackage(
      id: 'holiday_jss',
      name: 'JSS 1–3 Holiday Classes',
      price: 10500,
      billing: '5 classes weekly',
      features: [
        'Mathematics',
        'English Language',
        'Phonics',
        'French',
        'Computer',
      ],
    ),
    _ClassPackage(
      id: 'holiday_ss_science',
      name: 'SS 1–3 Science Holiday Classes',
      price: 11000,
      billing: '5 classes weekly',
      features: ['Mathematics', 'English', 'Physics', 'Chemistry', 'Biology'],
    ),
    _ClassPackage(
      id: 'holiday_ss_art',
      name: 'SS 1–3 Art Holiday Classes',
      price: 11000,
      billing: '5 classes weekly',
      features: [
        'Mathematics',
        'English',
        'Literature-in-English',
        'CRS/IRS',
        'Government',
      ],
    ),
    _ClassPackage(
      id: 'holiday_ss_commercial',
      name: 'SS 1–3 Commercial Holiday Classes',
      price: 11000,
      billing: '5 classes weekly',
      features: [
        'Mathematics',
        'English',
        'Financial Accounting',
        'Commerce',
        'Economics',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final plans = kidsOnly ? _kidPlans : _studentPlans;
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(title: const Text('Class packages')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            kidsOnly
                ? 'Nursery & Primary Classes'
                : 'Secondary & Holiday Classes',
            style: TextStyle(
              color: context.textColor,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose the package that matches the learner’s class.',
            style: TextStyle(color: context.greyColor),
          ),
          const SizedBox(height: 18),
          ...plans.map((plan) => _PackageCard(plan: plan)),
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
              '₦${_format(plan.price)} · ${plan.billing}',
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
                onPressed: () async {
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
                        content: Text(
                          'Payment confirmed. Your class package is active.',
                        ),
                      ),
                    );
                  } on ApiException catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('Choose package'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(int value) => value.toString().replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
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
