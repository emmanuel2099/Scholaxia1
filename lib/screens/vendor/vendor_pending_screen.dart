import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import 'vendor_kyc_screen.dart';
import 'vendor_login_screen.dart';
import 'vendor_shell.dart';
import 'vendor_theme.dart';

/// Shown after signup until an admin approves the vendor (+ WhatsApp).
class VendorPendingScreen extends StatefulWidget {
  const VendorPendingScreen({super.key});

  @override
  State<VendorPendingScreen> createState() => _VendorPendingScreenState();
}

class _VendorPendingScreenState extends State<VendorPendingScreen> {
  final _api = ApiService();
  bool _loading = true;
  Map<String, dynamic> _status = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await _api.vendorAccountStatus();
      if (!mounted) return;
      setState(() => _status = s);
      if (s['is_approved'] == true) {
        if (s['kyc_completed'] == true) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const VendorShell()),
            (_) => false,
          );
        } else {
          final done = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const VendorKycScreen()),
          );
          if (!mounted) return;
          if (done == true) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const VendorShell()),
              (_) => false,
            );
          }
        }
      }
    } catch (_) {
      // Keep waiting UI.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _api.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const VendorLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final business = _status['business_name']?.toString() ?? 'Your store';
    return Scaffold(
      backgroundColor: VendorTheme.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: VendorTheme.maroon,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              const CircleAvatar(
                radius: 36,
                backgroundColor: VendorTheme.maroonSoft,
                child: Icon(Icons.hourglass_top_rounded, color: VendorTheme.maroon, size: 34),
              ),
              const SizedBox(height: 18),
              Text(
                'Waiting for admin approval',
                style: const TextStyle(
                  color: VendorTheme.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$business is registered. A Scholaxia admin will approve your account and add your WhatsApp number. After approval, complete KYC (NIN), then you can list products.',
                style: const TextStyle(color: VendorTheme.muted, height: 1.45),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: VendorTheme.cardDecoration(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Status', 'Pending approval'),
                    _row('Email', _status['email']?.toString() ?? '—'),
                    _row('Business', business),
                    _row('WhatsApp', _status['whatsapp']?.toString().isNotEmpty == true
                        ? _status['whatsapp'].toString()
                        : 'Set by admin on approval'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VendorTheme.maroon,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Check approval status'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: _logout, child: const Text('Log out')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: VendorTheme.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: VendorTheme.text, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
