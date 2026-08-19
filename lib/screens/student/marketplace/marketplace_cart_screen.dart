import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../services/paystack_checkout_service.dart';
import '../../../theme/app_theme.dart';
import 'marketplace_orders_screen.dart';

class MarketplaceCartScreen extends StatefulWidget {
  const MarketplaceCartScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<MarketplaceCartScreen> createState() => _MarketplaceCartScreenState();
}

class _MarketplaceCartScreenState extends State<MarketplaceCartScreen> {
  bool _loading = true;
  bool _checkingOut = false;
  List<Map<String, dynamic>> _items = const [];
  double _total = 0;
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cart = await widget.api.marketplaceCart();
      final raw = cart['items'];
      final items = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) items.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _total = (cart['total_amount'] as num?)?.toDouble() ?? 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(String id) async {
    try {
      await widget.api.removeMarketplaceCartItem(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _checkout() async {
    final address = _addressCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (address.length < 5 || phone.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter delivery address and phone.')),
      );
      return;
    }
    if (_items.isEmpty) return;
    setState(() => _checkingOut = true);
    try {
      final checkout = await widget.api.checkoutMarketplaceCart(
        deliveryAddress: address,
        contactPhone: phone,
      );
      final orderId = checkout['order_id']?.toString() ?? '';
      if (orderId.isEmpty) {
        throw const ApiException.message('Checkout did not return an order id.');
      }
      if (!mounted) return;
      final paid = await PaystackCheckoutService.purchase(
        context: context,
        api: widget.api,
        productType: 'marketplace_order',
        productId: orderId,
      );
      if (!mounted) return;
      if (!paid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment was not completed. You can retry from My orders.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment successful. Track your order under My orders.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MarketplaceOrdersScreen(api: widget.api),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _checkingOut = false);
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
      appBar: AppBar(
        title: const Text('Cart'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MarketplaceOrdersScreen(api: widget.api),
                ),
              );
            },
            child: const Text('My orders'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Your cart is empty'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    for (final item in _items) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.surfColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item['product'] is Map
                                            ? item['product']['title']
                                            : null)
                                        ?.toString() ??
                                        'Product',
                                    style: TextStyle(
                                      color: context.textColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Qty ${item['quantity'] ?? 1} · ${_money((item['line_total'] as num?) ?? 0)}',
                                    style: TextStyle(color: context.greyColor),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _remove(item['id']?.toString() ?? ''),
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Total ${_money(_total)}',
                      style: TextStyle(
                        color: context.accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _addressCtrl,
                      style: TextStyle(color: context.textColor),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Delivery address',
                        filled: true,
                        fillColor: context.surfColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneCtrl,
                      style: TextStyle(color: context.textColor),
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Contact phone',
                        filled: true,
                        fillColor: context.surfColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _checkingOut ? null : _checkout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.white,
                    ),
                    child: _checkingOut
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Checkout & pay ${_money(_total)}'),
                  ),
                ),
              ),
            ),
    );
  }
}
