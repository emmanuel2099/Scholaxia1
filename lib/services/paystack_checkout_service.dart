import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_service.dart';

class PaystackCheckoutService {
  PaystackCheckoutService._();

  static Future<bool> purchase({
    required BuildContext context,
    required ApiService api,
    required String productType,
    required String productId,
  }) async {
    final initialized = await api.initializePaystack(
      productType: productType,
      productId: productId,
    );
    if (initialized['already_owned'] == true) return true;

    final url = initialized['authorization_url']?.toString() ?? '';
    final reference = initialized['reference']?.toString() ?? '';
    if (url.isEmpty || reference.isEmpty) {
      throw const ApiException.message('Paystack checkout is unavailable.');
    }

    final uri = Uri.parse(url);
    var opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!opened) {
      throw const ApiException.message('Could not open Paystack checkout.');
    }
    if (!context.mounted) return false;

    final shouldVerify =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Complete payment'),
            content: const Text(
              'Finish payment in Paystack, then tap Verify payment.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Verify payment'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldVerify) return false;
    final result = await api.verifyPaystack(reference);
    return result['paid'] == true || result['has_access'] == true;
  }
}
