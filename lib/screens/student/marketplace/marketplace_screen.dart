import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';

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

  static const _tabs = [
    ('all', 'All'),
    ('gadgets', 'Gadgets'),
    ('laptops', 'Laptops'),
    ('phones', 'Phones'),
    ('books', 'Books'),
    ('other', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
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
        final img = m['image_url']?.toString();
        if (img != null && img.isNotEmpty) {
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
    final n = (p['price'] as num?)?.toDouble() ?? 0;
    if (n <= 0) return 'Ask price';
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer('₦');
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  void _openBookSheet(Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.headerColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _BookProductSheet(api: _api, product: product),
    );
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
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Text(
                    'Marketplace',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Text(
                'Shop gadgets, laptops, phones and more. Book an item and Scholaxia will chat with you.',
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
                                  'Admin will post items here for students to book.',
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
                                childAspectRatio: 0.68,
                              ),
                              itemCount: _products.length,
                              itemBuilder: (_, i) {
                                final p = _products[i];
                                final title = p['title']?.toString() ?? 'Item';
                                final image = p['image_url']?.toString();
                                final cat = p['category']?.toString() ?? '';
                                return Material(
                                  color: context.cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _openBookSheet(p),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: context.borderColor),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              width: double.infinity,
                                              color: context.accentColor
                                                  .withOpacity(0.08),
                                              child: image != null &&
                                                      image.isNotEmpty
                                                  ? Image.network(
                                                      image,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) => Icon(
                                                        Icons
                                                            .shopping_bag_outlined,
                                                        color: context
                                                            .accentColor,
                                                        size: 36,
                                                      ),
                                                    )
                                                  : Icon(
                                                      Icons
                                                          .shopping_bag_outlined,
                                                      color:
                                                          context.accentColor,
                                                      size: 36,
                                                    ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                12, 10, 12, 12),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: context.textColor,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _price(p),
                                                  style: TextStyle(
                                                    color: context.accentColor,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                if (cat.isNotEmpty)
                                                  Text(
                                                    cat.toUpperCase(),
                                                    style: TextStyle(
                                                      color: context.greyColor,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  width: double.infinity,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: context.accentColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: const Text(
                                                    'Book now',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
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

class _BookProductSheet extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> product;

  const _BookProductSheet({required this.api, required this.product});

  @override
  State<_BookProductSheet> createState() => _BookProductSheetState();
}

class _BookProductSheetState extends State<_BookProductSheet> {
  final _nameCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    try {
      final p = await widget.api.getStudentProfile();
      if (!mounted) return;
      _nameCtrl.text = p.fullName;
      _emailCtrl.text = p.email;
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _whatsappCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final wa = _whatsappCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isEmpty || wa.isEmpty || phone.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Name, WhatsApp, phone and email are required.')),
      );
      return;
    }
    final id = widget.product['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final productTitle = widget.product['title']?.toString() ?? 'Product';
    setState(() => _submitting = true);
    try {
      final isDemo = widget.product['is_demo'] == true || id.startsWith('demo-');
      if (isDemo) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Test booking for "$productTitle" noted. When admin posts live products, bookings go to Scholaxia WhatsApp.',
            ),
          ),
        );
        return;
      }
      await widget.api.bookMarketplaceProduct(
        productId: id,
        fullName: name,
        whatsapp: wa,
        phone: phone,
        email: email,
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Booking sent! Scholaxia will contact you on WhatsApp or phone.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not submit booking.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.product['title']?.toString() ?? 'Product';
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Book: $title',
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Fill your details. Admin will chat with you about this product.',
              style: TextStyle(color: context.greyColor, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _field(_nameCtrl, 'Full name *'),
            const SizedBox(height: 10),
            _field(_whatsappCtrl, 'WhatsApp number *',
                keyboard: TextInputType.phone),
            const SizedBox(height: 10),
            _field(_phoneCtrl, 'Phone number *',
                keyboard: TextInputType.phone),
            const SizedBox(height: 10),
            _field(_emailCtrl, 'Email *',
                keyboard: TextInputType.emailAddress),
            const SizedBox(height: 10),
            _field(_noteCtrl, 'Note (optional)', maxLines: 2),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Submit booking',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: TextStyle(color: context.textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.greyLColor),
        filled: true,
        fillColor: context.surfColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
