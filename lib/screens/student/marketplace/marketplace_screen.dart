import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'marketplace_cart_screen.dart';
import 'marketplace_format.dart';
import 'marketplace_orders_screen.dart';
import 'marketplace_product_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _api = ApiService();
  bool _loading = true;
  String _category = 'all';
  List<Map<String, dynamic>> _products = [];
  int _cartQty = 0;

  static const _tabs = [
    ('all', 'All'),
    ('books', 'Books'),
    ('soft_copy', 'Soft copy / PDF'),
    ('software', 'Software'),
    ('educational_materials', 'Educational materials'),
    ('phones', 'Phones'),
    ('gadgets', 'Gadgets'),
    ('flash_drive', 'Flash drive'),
    ('charger', 'Charger'),
    ('projector', 'Projector'),
    ('desktop_computer', 'Desktop computer'),
    ('bags', 'Bags'),
    ('laptops', 'Laptops'),
    ('other', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _refreshCartCount();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.marketplaceProducts(
        category: _category == 'all' ? null : _category,
      );
      if (!mounted) return;
      final products = raw.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final img = m['image_url']?.toString() ??
            m['secure_url']?.toString() ??
            m['image']?.toString() ??
            m['photo_url']?.toString() ??
            '';
        if (img.isNotEmpty) {
          m['image_url'] = _api.resolveMediaUrl(img);
        }
        return m;
      }).toList();
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _products = [];
          _loading = false;
        });
      }
    }
  }

  String _price(Map<String, dynamic> p) {
    return formatMarketplaceNaira((p['price'] as num?) ?? 0);
  }

  Future<void> _refreshCartCount() async {
    try {
      final cart = await _api.marketplaceCart();
      final raw = cart['items'];
      var qty = 0;
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            qty += (e['quantity'] as num?)?.toInt() ?? 1;
          }
        }
      }
      if (!mounted) return;
      setState(() => _cartQty = qty);
    } catch (_) {}
  }

  void _openCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MarketplaceCartScreen(api: _api)),
    ).then((_) => _refreshCartCount());
  }

  void _openDetails(Map<String, dynamic> product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarketplaceProductScreen(
          api: _api,
          product: product,
          onCartChanged: _refreshCartCount,
        ),
      ),
    ).then((_) => _refreshCartCount());
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final id = product['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This item has no checkout price yet.')),
      );
      return;
    }
    try {
      await _api.addToMarketplaceCart(productId: id);
      await _refreshCartCount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product['title'] ?? 'Item'} added to cart'),
          action: SnackBarAction(label: 'Cart', onPressed: _openCart),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Expanded(
                    child: Text(
                      'Marketplace',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'My orders',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MarketplaceOrdersScreen(api: _api),
                        ),
                      );
                    },
                    icon: Icon(Icons.receipt_long_outlined, color: context.textColor),
                  ),
                  IconButton(
                    tooltip: 'Cart',
                    onPressed: _openCart,
                    icon: Badge(
                      isLabelVisible: _cartQty > 0,
                      label: Text(_cartQty > 99 ? '99+' : '$_cartQty'),
                      child: Icon(
                        Icons.shopping_cart_outlined,
                        color: context.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Text(
                'Add books and products to cart, checkout, pay, then track your order.',
                style: TextStyle(color: context.greyColor, fontSize: 13, height: 1.4),
              ),
            ),
            SizedBox(
              height: 44,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: true,
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final (id, label) = _tabs[i];
                    final sel = _category == id;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          if (_category == id) return;
                          setState(() => _category = id);
                          _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                sel ? context.accentColor : context.cardColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel
                                  ? context.accentColor
                                  : context.borderColor,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: sel ? Colors.white : context.textColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                'Swipe sideways to see Books, Gadgets and more',
                style: TextStyle(color: context.greyColor, fontSize: 11),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? Center(
                      child:
                          CircularProgressIndicator(color: context.accentColor))
                  : RefreshIndicator(
                      color: context.accentColor,
                      onRefresh: _load,
                      child: _products.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 80),
                                Icon(Icons.storefront_outlined,
                                    size: 48, color: context.greyColor),
                                const SizedBox(height: 12),
                                Text(
                                  'No products in this category',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.textColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Vendors post books and products here for you to book.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: context.greyColor, fontSize: 13),
                                ),
                              ],
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: 268,
                              ),
                              itemCount: _products.length,
                              itemBuilder: (_, i) {
                                final p = _products[i];
                                final title = p['title']?.toString() ?? 'Item';
                                final image = p['image_url']?.toString();
                                final desc = parseMarketplaceMeta(
                                      p['description']?.toString(),
                                    )['description']
                                        ?.toString() ??
                                    '';
                                return Material(
                                  color: context.cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _openDetails(p),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: context.borderColor),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(
                                            height: 112,
                                            child: _MarketplaceImage(
                                              url: image,
                                              accent: context.accentColor,
                                            ),
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      10, 8, 10, 10),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: context.textColor,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  if (desc.isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      desc,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color:
                                                            context.greyColor,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _price(p),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color:
                                                          context.accentColor,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    height: 34,
                                                    child: ElevatedButton(
                                                      onPressed: () =>
                                                          _addToCart(p),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            context.accentColor,
                                                        foregroundColor:
                                                            Colors.white,
                                                        elevation: 0,
                                                        padding: EdgeInsets.zero,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(10),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        'Add to cart',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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

/// Product photo for marketplace grid.
class _MarketplaceImage extends StatelessWidget {
  final String? url;
  final Color accent;

  const _MarketplaceImage({required this.url, required this.accent});

  @override
  Widget build(BuildContext context) {
    final imageUrl = (url ?? '').trim();
    return Container(
      width: double.infinity,
      color: accent.withOpacity(0.08),
      child: imageUrl.isEmpty
          ? Icon(Icons.shopping_bag_outlined, color: accent, size: 36)
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Icon(
                Icons.shopping_bag_outlined,
                color: accent,
                size: 36,
              ),
            ),
    );
  }
}
