import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import 'vendor_notifications_screen.dart';
import 'vendor_theme.dart';

class VendorHomeScreen extends StatefulWidget {
  const VendorHomeScreen({super.key, this.onOpenRequests});

  final VoidCallback? onOpenRequests;

  @override
  State<VendorHomeScreen> createState() => _VendorHomeScreenState();
}

class _VendorHomeScreenState extends State<VendorHomeScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String _name = 'Vendor';
  int _pending = 0;
  int _requests = 0;
  int _approvals = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      List<dynamic> bookings = const [];
      List<dynamic> orders = const [];
      try {
        bookings = await _api.vendorBookings();
      } catch (_) {}
      try {
        orders = await _api.vendorOrders();
      } catch (_) {}

      var pending = 0;
      var approved = 0;
      for (final raw in [...bookings, ...orders]) {
        if (raw is! Map) continue;
        final status = raw['tracking_status']?.toString() ??
            raw['status']?.toString();
        final ui = VendorTheme.uiStatus(status);
        if (ui == 'pending') pending++;
        if (ui == 'approved') approved++;
      }

      if (!mounted) return;
      setState(() {
        _name = 'Vendor Partner';
        _pending = pending;
        _requests = bookings.length + orders.length;
        _approvals = approved;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatFriendlyDate(DateTime dt) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final today = _formatFriendlyDate(DateTime.now());

    return Scaffold(
      backgroundColor: VendorTheme.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: VendorTheme.maroon,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: VendorTheme.maroonSoft,
                    child: Icon(Icons.storefront_rounded, color: VendorTheme.maroon),
                  ),
                  const Spacer(),
                  Stack(
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const VendorNotificationsScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: VendorTheme.border),
                          ),
                          child: const Icon(Icons.notifications_none_rounded, color: VendorTheme.text),
                        ),
                      ),
                      if (_pending > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Hi, $_name.',
                style: const TextStyle(
                  color: VendorTheme.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$today\nYou have approvals and requests ready to review.',
                style: const TextStyle(color: VendorTheme.muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(
                  color: VendorTheme.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: VendorTheme.maroon,
                decoration: InputDecoration(
                  hintText: 'Search requests…',
                  hintStyle: const TextStyle(color: VendorTheme.muted),
                  prefixIcon: const Icon(Icons.search_rounded, color: VendorTheme.muted),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: VendorTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: VendorTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: VendorTheme.maroon, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => widget.onOpenRequests?.call(),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: VendorTheme.cardDecoration(radius: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pending Approvals',
                            style: TextStyle(
                              color: VendorTheme.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_pending items waiting',
                            style: const TextStyle(color: VendorTheme.muted),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: widget.onOpenRequests,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: VendorTheme.maroon,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('View Approvals'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: VendorTheme.maroonSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        color: VendorTheme.maroon,
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_loading) const LinearProgressIndicator(color: VendorTheme.maroon),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'Requests',
                      value: '$_requests',
                      delta: '+0 vs last month',
                      up: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      title: 'Approvals',
                      value: '$_approvals',
                      delta: '$_approvals completed',
                      up: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String delta;
  final bool up;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.delta,
    required this.up,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: VendorTheme.cardDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: VendorTheme.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: VendorTheme.text,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 16,
                color: up ? VendorTheme.approvedFg : VendorTheme.rejectedFg,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  delta,
                  style: TextStyle(
                    color: up ? VendorTheme.approvedFg : VendorTheme.rejectedFg,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
