import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import 'vendor_add_product_screen.dart';
import 'vendor_kyc_screen.dart';
import 'vendor_theme.dart';

class VendorProductsScreen extends StatefulWidget {
  const VendorProductsScreen({super.key});

  @override
  State<VendorProductsScreen> createState() => _VendorProductsScreenState();
}

class _VendorProductsScreenState extends State<VendorProductsScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<dynamic> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _api.vendorProductsMine();
      if (!mounted) return;
      setState(() => _items = items);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAdd({String category = 'books'}) async {
    try {
      final kyc = await _api.vendorGetKyc();
      if (!mounted) return;
      if (kyc['kyc_completed'] != true) {
        final done = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const VendorKycScreen()),
        );
        if (done != true || !mounted) return;
      }
    } on ApiException catch (e) {
      // Older API without KYC — still allow posting books/products.
      final msg = e.message.toLowerCase();
      if (!(msg.contains('not found') || msg.contains('404'))) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
        return;
      }
    } catch (_) {
      // Network blip — still open the form; save will report errors.
    }

    if (!mounted) return;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VendorAddProductScreen(initialCategory: category),
      ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VendorTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Products',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: VendorTheme.text,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openAdd(category: 'books'),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VendorTheme.maroon,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: VendorTheme.maroon))
                  : RefreshIndicator(
                      color: VendorTheme.maroon,
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 64),
                                const Icon(Icons.menu_book_rounded, size: 52, color: VendorTheme.maroon),
                                const SizedBox(height: 12),
                                const Center(
                                  child: Text(
                                    'Post books & products',
                                    style: TextStyle(
                                      color: VendorTheme.text,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    'Sell textbooks, past questions, gadgets, phones and more. Students book them in Marketplace.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: VendorTheme.muted, height: 1.4),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 40),
                                  child: ElevatedButton.icon(
                                    onPressed: () => _openAdd(category: 'books'),
                                    icon: const Icon(Icons.menu_book_rounded),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: VendorTheme.maroon,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(50),
                                    ),
                                    label: const Text('Post a Book'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Center(
                                  child: TextButton(
                                    onPressed: () => _openAdd(category: 'gadgets'),
                                    child: const Text('Add another product type'),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final p = _items[i] as Map;
                                final available = p['is_available'] == true;
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: VendorTheme.cardDecoration(radius: 16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: VendorTheme.maroonSoft,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          available ? Icons.check_circle : Icons.pause_circle,
                                          color: VendorTheme.maroon,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p['title']?.toString() ?? 'Untitled',
                                              style: const TextStyle(
                                                color: VendorTheme.text,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Category: ${p['category'] ?? '-'}',
                                              style: const TextStyle(color: VendorTheme.muted, fontSize: 12),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Stock ${p['stock_qty'] ?? 0}  ·  ${VendorTheme.formatNaira(p['price'] is num ? p['price'] as num : 0)}',
                                              style: const TextStyle(
                                                color: VendorTheme.text,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
