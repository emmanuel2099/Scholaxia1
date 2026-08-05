import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import 'vendor_kyc_screen.dart';
import 'vendor_pending_screen.dart';
import 'vendor_shell.dart';

/// Route vendor after login/signup based on admin approval + KYC.
Future<void> openVendorHome(BuildContext context, ApiService api) async {
  try {
    final status = await api.vendorAccountStatus();
    if (!context.mounted) return;
    final approved = status['is_approved'] == true;
    final kyc = status['kyc_completed'] == true;
    if (!approved) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VendorPendingScreen()),
        (_) => false,
      );
      return;
    }
    if (!kyc) {
      final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const VendorKycScreen()),
      );
      if (!context.mounted) return;
      if (done != true) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const VendorPendingScreen()),
          (_) => false,
        );
        return;
      }
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const VendorShell()),
      (_) => false,
    );
  } catch (_) {
    if (!context.mounted) return;
    // Older API without /status — allow shell, listing still gated server-side.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const VendorShell()),
      (_) => false,
    );
  }
}
