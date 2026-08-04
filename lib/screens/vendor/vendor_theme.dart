import 'package:flutter/material.dart';

/// Market Vendor visual system — maroon / white / soft gray.
class VendorTheme {
  VendorTheme._();

  static const Color maroon = Color(0xFF8B1E3F);
  static const Color maroonDark = Color(0xFF6E1530);
  static const Color maroonSoft = Color(0xFFF8EBEF);
  static const Color bg = Color(0xFFF4F5F7);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1F2937);
  static const Color muted = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color pendingBg = Color(0xFFFEF3C7);
  static const Color pendingFg = Color(0xFFB45309);
  static const Color approvedBg = Color(0xFFDCFCE7);
  static const Color approvedFg = Color(0xFF15803D);
  static const Color rejectedBg = Color(0xFFFEE2E2);
  static const Color rejectedFg = Color(0xFFB91C1C);

  static BoxDecoration cardDecoration({double radius = 18}) => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static String formatNaira(num amount) {
    final v = amount.toDouble();
    final parts = v.toStringAsFixed(2).split('.');
    final whole = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final fromEnd = whole.length - i;
      buf.write(whole[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return '₦ ${buf.toString()}.${parts[1]}';
  }

  /// Map tracking/order/booking status into Pending / Approved / Rejected UI buckets.
  static String uiStatus(String? raw) {
    final s = (raw ?? 'pending').toLowerCase().trim();
    if (s.contains('cancel') || s.contains('reject') || s == 'closed') {
      return 'rejected';
    }
    if (s.contains('deliver') ||
        s.contains('complete') ||
        s.contains('ship') ||
        s.contains('transit') ||
        s.contains('approv') ||
        s == 'running' ||
        s == 'contacted' ||
        s == 'paid') {
      return 'approved';
    }
    return 'pending';
  }

  static String statusLabel(String ui, {String? raw}) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s == 'running') return 'RUNNING';
    switch (ui) {
      case 'approved':
        return 'APPROVED';
      case 'rejected':
        return 'REJECTED';
      default:
        return 'PENDING';
    }
  }

  static Color statusBg(String ui) {
    switch (ui) {
      case 'approved':
        return approvedBg;
      case 'rejected':
        return rejectedBg;
      default:
        return pendingBg;
    }
  }

  static Color statusFg(String ui) {
    switch (ui) {
      case 'approved':
        return approvedFg;
      case 'rejected':
        return rejectedFg;
      default:
        return pendingFg;
    }
  }
}
