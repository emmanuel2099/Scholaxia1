import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../services/paystack_checkout_service.dart';
import '../../../theme/app_theme.dart';

class CbtPackagesScreen extends StatelessWidget {
  const CbtPackagesScreen({super.key, this.kidsOnly = false});

  final bool kidsOnly;

  static const _packages = [
    ('JAMB Only', 3000, 'JAMB', 'jamb'),
    ('WAEC Only', 3000, 'WAEC', 'waec'),
    ('NECO Only', 2500, 'NECO', 'neco'),
    ('JAMB & WAEC', 5000, 'JAMB + WAEC', 'jamb_waec'),
    (
      'JAMB, WAEC & NECO',
      7000,
      'All three senior exam boards',
      'jamb_waec_neco',
    ),
    ('Junior WAEC', 3000, 'BECE / Junior WAEC', 'junior_waec'),
  ];

  @override
  Widget build(BuildContext context) {
    final packages = kidsOnly
        ? const [
            ('Common Entrance', 2000, 'Primary 6', 'common_entrance'),
          ]
        : _packages;
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(title: const Text('Annual CBT packages')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradients.hero(context),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Practice for one full year',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Includes CBT access and Sia AI support during the active package.',
                  style: TextStyle(color: Colors.white, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...packages.map(
            (package) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                leading: const CircleAvatar(child: Icon(Icons.quiz_rounded)),
                title: Text(
                  package.$1,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('${package.$3}\nExpires after 1 year'),
                isThreeLine: true,
                trailing: Text(
                  '₦${_format(package.$2)}',
                  style: TextStyle(
                    color: context.accentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                onTap: () => _buy(context, package.$4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _buy(BuildContext context, String packageId) async {
    try {
      final paid = await PaystackCheckoutService.purchase(
        context: context,
        api: ApiService(),
        productType: 'cbt_package',
        productId: packageId,
      );
      if (!context.mounted || !paid) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmed. Your annual CBT package is active.'),
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  static String _format(int value) {
    final text = value.toString();
    return text.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
}
