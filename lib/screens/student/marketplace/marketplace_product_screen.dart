import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'marketplace_cart_screen.dart';
import 'marketplace_format.dart';

class MarketplaceProductScreen extends StatefulWidget {
  const MarketplaceProductScreen({
    super.key,
    required this.api,
    required this.product,
    this.onCartChanged,
  });

  final ApiService api;
  final Map<String, dynamic> product;
  final VoidCallback? onCartChanged;

  @override
  State<MarketplaceProductScreen> createState() =>
      _MarketplaceProductScreenState();
}

class _MarketplaceProductScreenState extends State<MarketplaceProductScreen> {
  late Map<String, dynamic> _product;
  bool _adding = false;
  int _photo = 0;

  @override
  void initState() {
    super.initState();
    _product = Map<String, dynamic>.from(widget.product);
    _refresh();
  }

  Future<void> _refresh() async {
    final id = _product['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final fresh = await widget.api.marketplaceProduct(id);
      if (!mounted || fresh.isEmpty) return;
      final img = fresh['image_url']?.toString() ?? '';
      if (img.isNotEmpty) {
        fresh['image_url'] = widget.api.resolveMediaUrl(img);
      }
      setState(() => _product = fresh);
    } catch (_) {}
  }

  List<String> get _images => marketplaceProductImages(
        _product,
        widget.api.resolveMediaUrl,
      );

  Future<void> _addToCart() async {
    final id = _product['id']?.toString() ?? '';
    if (id.isEmpty || _adding) return;
    final price = (_product['price'] as num?)?.toDouble() ?? 0;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This item has no checkout price yet.')),
      );
      return;
    }
    setState(() => _adding = true);
    try {
      await widget.api.addToMarketplaceCart(productId: id);
      widget.onCartChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_product['title'] ?? 'Item'} added to cart'),
          action: SnackBarAction(
            label: 'Cart',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MarketplaceCartScreen(api: widget.api),
                ),
              ).then((_) => widget.onCartChanged?.call());
            },
          ),
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
      if (mounted) setState(() => _adding = false);
    }
  }

  String _categoryLabel(String raw) {
    final value = raw.replaceAll('_', ' ').trim();
    if (value.isEmpty) return 'Item';
    return value
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseMarketplaceMeta(_product['description']?.toString());
    final meta = parsed['meta'] as Map<String, dynamic>? ?? {};
    final desc = parsed['description']?.toString() ?? '';
    final title = _product['title']?.toString() ?? 'Item';
    final category = _categoryLabel(_product['category']?.toString() ?? '');
    final condition = (meta['condition']?.toString() ?? '') == 'fairly_used'
        ? 'Fairly used'
        : 'New';
    final isDigital = meta['product_type']?.toString() == 'digital';
    final stock = (_product['stock_qty'] as num?)?.toInt() ?? 0;
    final price = formatMarketplaceNaira((_product['price'] as num?) ?? 0);
    final images = _images;
    final photo = images.isEmpty
        ? 0
        : _photo.clamp(0, images.length - 1);

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('Item details'),
        actions: [
          IconButton(
            tooltip: 'Cart',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MarketplaceCartScreen(api: widget.api),
                ),
              ).then((_) => widget.onCartChanged?.call());
            },
            icon: Icon(Icons.shopping_cart_outlined, color: context.accentColor),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 1.15,
              child: images.isEmpty
                  ? ColoredBox(
                      color: context.accentColor.withValues(alpha: 0.08),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        size: 56,
                        color: context.accentColor,
                      ),
                    )
                  : Image.network(
                      images[photo],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: context.accentColor.withValues(alpha: 0.08),
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          size: 56,
                          color: context.accentColor,
                        ),
                      ),
                    ),
            ),
          ),
          if (images.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final on = i == photo;
                  return GestureDetector(
                    onTap: () => setState(() => _photo = i),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: on ? context.accentColor : context.borderColor,
                          width: on ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.network(
                          images[i],
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            category.toUpperCase(),
            style: TextStyle(
              color: context.accentColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: context.textColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            price,
            style: TextStyle(
              color: context.accentColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, condition),
              if (isDigital) _chip(context, 'Digital / PDF'),
              _chip(
                context,
                stock > 0 ? '$stock in stock' : 'In stock',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'About this item',
            style: TextStyle(
              color: context.textColor,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc.isEmpty
                ? 'No extra description was added for this listing.'
                : desc,
            style: TextStyle(
              color: context.greyColor,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _adding ? null : _addToCart,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _adding ? 'Adding…' : 'Add to cart',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.textColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
