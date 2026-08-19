import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../services/paystack_checkout_service.dart';
import '../../../theme/app_theme.dart';

class MarketplaceOrdersScreen extends StatefulWidget {
  const MarketplaceOrdersScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<MarketplaceOrdersScreen> createState() =>
      _MarketplaceOrdersScreenState();
}

class _MarketplaceOrdersScreenState extends State<MarketplaceOrdersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await widget.api.marketplaceOrdersMine();
      final orders = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) orders.add(Map<String, dynamic>.from(e));
      }
      if (!mounted) return;
      setState(() => _orders = orders);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay(String orderId) async {
    try {
      final paid = await PaystackCheckoutService.purchase(
        context: context,
        api: widget.api,
        productType: 'marketplace_order',
        productId: orderId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(paid ? 'Payment successful.' : 'Payment not completed.'),
        ),
      );
      if (paid) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  String _money(num n) {
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer('\u20A6');
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(title: const Text('My orders')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _orders.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No orders yet')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final o = _orders[i];
                        final status = (o['status']?.toString() ?? 'pending').toLowerCase();
                        final items = o['items'] is List ? o['items'] as List : const [];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.surfColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Order ${(o['id']?.toString() ?? '').substring(0, (o['id']?.toString().length ?? 0).clamp(0, 8))}',
                                      style: TextStyle(
                                        color: context.textColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      color: context.accentColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _money((o['total_amount'] as num?) ?? 0),
                                style: TextStyle(
                                  color: context.textColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final raw in items)
                                if (raw is Map)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${raw['product_title'] ?? 'Item'} · '
                                      '${(raw['tracking_status'] ?? 'pending').toString().toUpperCase()}',
                                      style: TextStyle(
                                        color: context.greyColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              if (status == 'pending_payment') ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        _pay(o['id']?.toString() ?? ''),
                                    child: const Text('Pay now'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
