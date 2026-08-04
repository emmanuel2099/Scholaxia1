import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import 'vendor_login_screen.dart';
import 'vendor_notifications_screen.dart';
import 'vendor_theme.dart';

class VendorProfileScreen extends StatelessWidget {
  const VendorProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await ApiService().clearTokens();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const VendorLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VendorTheme.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            const Text(
              'Profile',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: VendorTheme.text,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [VendorTheme.maroon, VendorTheme.maroonDark],
                ),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.storefront_rounded, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Market Vendor',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Manage store, requests and approvals',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: 'Orders and account updates',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VendorNotificationsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.receipt_long_outlined,
              title: 'My Requests',
              subtitle: 'Review pending student orders',
            ),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.security_outlined,
              title: 'Security',
              subtitle: 'Protect your vendor account',
            ),
            const SizedBox(height: 8),
            _tile(
              icon: Icons.logout,
              title: 'Log out',
              subtitle: 'Sign out from this device',
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: VendorTheme.border),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: VendorTheme.maroonSoft,
              child: Icon(icon, color: VendorTheme.maroon),
            ),
            title: Text(
              title,
              style: const TextStyle(color: VendorTheme.text, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(subtitle, style: const TextStyle(color: VendorTheme.muted)),
          ),
        ),
      ),
    );
  }
}
