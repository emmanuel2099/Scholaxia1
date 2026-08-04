import 'package:flutter/material.dart';

import '../../services/offline_status_service.dart';
import 'vendor_home_screen.dart';
import 'vendor_orders_screen.dart';
import 'vendor_products_screen.dart';
import 'vendor_profile_screen.dart';
import 'vendor_theme.dart';

class VendorShell extends StatefulWidget {
  const VendorShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<VendorShell> createState() => _VendorShellState();
}

class _VendorShellState extends State<VendorShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OfflineStatusService.instance.setShowBanner(true);
    });
  }

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final screens = [
      VendorHomeScreen(onOpenRequests: () => _go(2)),
      const VendorProductsScreen(),
      const VendorOrdersScreen(),
      const VendorProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: VendorTheme.bg,
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  active: _index == 0,
                  onTap: () => _go(0),
                ),
                _NavItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Products',
                  active: _index == 1,
                  onTap: () => _go(1),
                ),
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Requests',
                  active: _index == 2,
                  onTap: () => _go(2),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  active: _index == 3,
                  onTap: () => _go(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? VendorTheme.maroon : VendorTheme.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
