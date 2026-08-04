import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import 'vendor_notifications_screen.dart';
import 'vendor_theme.dart';

class VendorOrdersScreen extends StatefulWidget {
  const VendorOrdersScreen({super.key});

  @override
  State<VendorOrdersScreen> createState() => _VendorOrdersScreenState();
}

class _VendorOrdersScreenState extends State<VendorOrdersScreen> {
  final _api = ApiService();
  bool _loading = true;
  int _tab = 0; // 0 mine-style pending focus, 1 all
  String? _statusFilter; // pending | approved | rejected | null
  String? _typeFilter;
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bookingsRaw = await _api.vendorBookings();
      List<dynamic> ordersRaw = const [];
      try {
        ordersRaw = await _api.vendorOrders();
      } catch (_) {}

      final mapped = <Map<String, dynamic>>[];

      for (final o in bookingsRaw) {
        if (o is! Map) continue;
        final m = Map<String, dynamic>.from(o);
        final id = (m['booking_id'] ?? m['order_id'] ?? '').toString();
        final short =
            id.length >= 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();
        m['_kind'] = 'booking';
        m['_mv_code'] = 'BK${short.padLeft(6, '0')}';
        m['_ui_status'] = VendorTheme.uiStatus(m['tracking_status']?.toString());
        m['_amount'] = m['unit_price'] is num ? m['unit_price'] as num : 0;
        mapped.add(m);
      }

      for (final o in ordersRaw) {
        if (o is! Map) continue;
        final m = Map<String, dynamic>.from(o);
        final id = (m['order_id'] ?? m['order_item_id'] ?? '').toString();
        final short =
            id.length >= 6 ? id.substring(0, 6).toUpperCase() : id.toUpperCase();
        m['_kind'] = 'order';
        m['_mv_code'] = 'MV${short.padLeft(6, '0')}';
        m['_ui_status'] = VendorTheme.uiStatus(m['tracking_status']?.toString());
        m['_amount'] = (m['unit_price'] is num ? m['unit_price'] as num : 0) *
            (m['quantity'] is num ? m['quantity'] as num : 1);
        mapped.add(m);
      }

      mapped.sort((a, b) {
        final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

      if (!mounted) return;
      setState(() => _orders = mapped);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    Iterable<Map<String, dynamic>> list = _orders;
    if (_tab == 0) {
      list = list.where((o) => o['_ui_status'] == 'pending');
    }
    if (_statusFilter != null) {
      list = list.where((o) => o['_ui_status'] == _statusFilter);
    }
    if (_typeFilter != null && _typeFilter!.isNotEmpty) {
      list = list.where((o) {
        final title = (o['product_title'] ?? '').toString().toLowerCase();
        return title.contains(_typeFilter!.toLowerCase());
      });
    }
    return list.toList();
  }

  Future<void> _openFilter() async {
    String? status = _statusFilter;
    String? type = _typeFilter;
    final types = <String>{
      for (final o in _orders)
        if ((o['product_title'] ?? '').toString().trim().isNotEmpty)
          o['product_title'].toString(),
    }.toList()
      ..sort();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: VendorTheme.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Filter Options',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: VendorTheme.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in ['pending', 'approved', 'rejected'])
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s[0].toUpperCase() + s.substring(1)),
                                if (status == s) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.close, size: 14),
                                ],
                              ],
                            ),
                            selected: status == s,
                            selectedColor: VendorTheme.maroon,
                            labelStyle: TextStyle(
                              color: status == s ? Colors.white : VendorTheme.text,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) {
                              setModal(() => status = status == s ? null : s);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Order / Product Type', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: type != null && types.contains(type) ? type : null,
                      decoration: InputDecoration(
                        hintText: 'Please select',
                        filled: true,
                        fillColor: VendorTheme.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All types')),
                        ...types.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                      ],
                      onChanged: (v) => setModal(() => type = v),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _statusFilter = null;
                                _typeFilter = null;
                              });
                              Navigator.pop(ctx);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: VendorTheme.maroon,
                              side: const BorderSide(color: VendorTheme.maroon),
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Clear all'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _statusFilter = status;
                                _typeFilter = type;
                              });
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: VendorTheme.maroon,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateStatus(Map<String, dynamic> order, String tracking) async {
    try {
      if (order['_kind'] == 'booking') {
        final id = order['booking_id']?.toString();
        if (id == null || id.isEmpty) return;
        final status = tracking == 'cancelled' || tracking == 'rejected'
            ? 'rejected'
            : 'running';
        await _api.vendorUpdateBookingStatus(bookingId: id, status: status);
      } else {
        final id = order['order_item_id']?.toString();
        if (id == null || id.isEmpty) return;
        await _api.vendorUpdateOrderTracking(
          orderItemId: id,
          trackingStatus: tracking,
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteOrder(Map<String, dynamic> order) async {
    if (order['_kind'] == 'booking') {
      final id = order['booking_id']?.toString();
      if (id == null || id.isEmpty) return;
      try {
        await _api.vendorUpdateBookingStatus(bookingId: id, status: 'closed');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request closed.')),
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
      return;
    }
    final id = order['order_item_id']?.toString();
    if (id == null || id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete order?'),
        content: const Text('This removes the order from your requests list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.vendorDeleteOrderItem(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order deleted.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mineCount = _orders.where((o) => o['_ui_status'] == 'pending').length;
    final allCount = _orders.length;
    final items = _filtered;

    return Scaffold(
      backgroundColor: VendorTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Requests',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: VendorTheme.text,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VendorNotificationsScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: VendorTheme.border),
                      ),
                      child: const Icon(Icons.notifications_none_rounded, color: VendorTheme.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: VendorTheme.maroonSoft,
                    child: Icon(Icons.storefront_rounded, color: VendorTheme.maroon, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: VendorTheme.border),
                ),
                child: Row(
                  children: [
                    _TabChip(
                      label: 'My Requests ($mineCount)',
                      active: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    _TabChip(
                      label: 'All Requests ($allCount)',
                      active: _tab == 1,
                      onTap: () => setState(() => _tab = 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: VendorTheme.maroon))
                  : RefreshIndicator(
                      color: VendorTheme.maroon,
                      onRefresh: _load,
                      child: items.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Text(
                                    'No requests yet',
                                    style: TextStyle(color: VendorTheme.muted),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _RequestCard(
                                order: items[i],
                                onApprove: () => _updateStatus(items[i], 'delivered'),
                                onReject: () => _updateStatus(items[i], 'cancelled'),
                                onDelete: () => _deleteOrder(items[i]),
                              ),
                            ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openFilter,
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.tune_rounded),
        label: const Text('Filter'),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? VendorTheme.maroonSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? VendorTheme.maroon : VendorTheme.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _RequestCard({
    required this.order,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ui = order['_ui_status']?.toString() ?? 'pending';
    final created = order['created_at']?.toString();
    String dateLabel = '--';
    if (created != null && created.isNotEmpty) {
      final dt = DateTime.tryParse(created)?.toLocal();
      if (dt != null) {
        dateLabel =
            '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
      }
    }
    final amount = order['_amount'] is num ? order['_amount'] as num : 0;
    final voucherNo =
        'SO-MV-${(order['order_id'] ?? '').toString().replaceAll('-', '').toUpperCase().padRight(10, '0').substring(0, 10)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: VendorTheme.cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order['_mv_code']}  ·  Market Vendor',
                  style: const TextStyle(
                    color: VendorTheme.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(dateLabel, style: const TextStyle(color: VendorTheme.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: VendorTheme.statusBg(ui),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              VendorTheme.statusLabel(
                ui,
                raw: order['tracking_status']?.toString(),
              ),
              style: TextStyle(
                color: VendorTheme.statusFg(ui),
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _row('Voucher Type', order['_kind'] == 'booking' ? 'Product Booking' : 'Sales Order'),
          _row('Voucher Number', voucherNo),
          _row('Buyer name', order['buyer_name']?.toString() ?? 'Student'),
          _row('Email', order['buyer_email']?.toString() ?? '—'),
          _row(
            'WhatsApp',
            order['buyer_whatsapp']?.toString() ??
                order['contact_phone']?.toString() ??
                '—',
          ),
          _row(
            'Phone',
            order['buyer_phone']?.toString() ??
                order['contact_phone']?.toString() ??
                '—',
          ),
          _row('Product', order['product_title']?.toString() ?? 'Product'),
          if ((order['product_description']?.toString() ?? '').trim().isNotEmpty)
            _row('Description', order['product_description'].toString()),
          _row('Total Amount', VendorTheme.formatNaira(amount), bold: true),
          if ((order['note']?.toString() ?? order['tracking_note']?.toString() ?? '')
              .trim()
              .isNotEmpty)
            _row(
              'Buyer note',
              (order['note'] ?? order['tracking_note']).toString(),
            ),
          if (ui == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: VendorTheme.rejectedFg,
                      side: const BorderSide(color: VendorTheme.rejectedFg),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VendorTheme.maroon,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18, color: VendorTheme.rejectedFg),
              label: Text(
                order['_kind'] == 'booking' ? 'Close request' : 'Delete order',
                style: const TextStyle(color: VendorTheme.rejectedFg),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: VendorTheme.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: VendorTheme.text,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
