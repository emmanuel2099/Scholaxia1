import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../services/paystack_checkout_service.dart';
import '../../../theme/app_theme.dart';

Future<bool> showCbtUnlockChoice(
  BuildContext context, {
  bool kidsOnly = false,
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Start this exam'),
      content: const Text(
        'Do you have a coupon code, or do you want to pay?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'coupon'),
          child: const Text('I have a coupon'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'pay'),
          child: const Text('I want to pay'),
        ),
      ],
    ),
  );
  if (!context.mounted || choice == null) return false;
  if (choice == 'pay') {
    final paid = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CbtPackagesScreen(kidsOnly: kidsOnly)),
    );
    return paid == true;
  }
  if (choice == 'coupon') {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Coupon code'),
        content: const _CouponBox(),
      ),
    );
    return ok == true;
  }
  return false;
}

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
      Navigator.pop(context, true);
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

class _CouponBox extends StatefulWidget {
  const _CouponBox();

  @override
  State<_CouponBox> createState() => _CouponBoxState();
}

class _CouponBoxState extends State<_CouponBox> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final data = await ApiService().redeemCbtCoupon(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${data['message'] ?? 'CBT access unlocked.'}')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Have a coupon?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text('Redeem an admin code to skip Paystack.'),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              decoration: const InputDecoration(
                hintText: 'SX-XXXX',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy ? null : _redeem,
              child: Text(_busy ? 'Redeeming…' : 'Redeem coupon'),
            ),
          ],
        ),
      ),
    );
  }
}
