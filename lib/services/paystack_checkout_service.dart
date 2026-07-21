import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

    var shouldVerify = false;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      if (!context.mounted) return false;
      shouldVerify =
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _EmbeddedPaystackCheckout(
                authorizationUrl: url,
                reference: reference,
              ),
            ),
          ) ??
          false;
    } else {
      // Desktop fallback. Mobile checkout—the store build—stays fully embedded.
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!opened) {
        throw const ApiException.message('Could not open Paystack checkout.');
      }
      if (!context.mounted) return false;
      shouldVerify =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Complete payment'),
              content: const Text(
                'After Paystack confirms payment, tap Verify payment.',
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
    }

    if (!shouldVerify) return false;
    final result = await api.verifyPaystack(reference);
    return result['paid'] == true || result['has_access'] == true;
  }
}

class _EmbeddedPaystackCheckout extends StatefulWidget {
  const _EmbeddedPaystackCheckout({
    required this.authorizationUrl,
    required this.reference,
  });

  final String authorizationUrl;
  final String reference;

  @override
  State<_EmbeddedPaystackCheckout> createState() =>
      _EmbeddedPaystackCheckoutState();
}

class _EmbeddedPaystackCheckoutState extends State<_EmbeddedPaystackCheckout> {
  late final WebViewController _controller;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (_isCompletionUrl(url)) {
              Navigator.pop(context, true);
              return;
            }
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            if (_isCompletionUrl(request.url)) {
              Navigator.pop(context, true);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  bool _isCompletionUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    if (uri.host == 'scholaxia.app' &&
        uri.path.startsWith('/paystack/callback')) {
      return true;
    }
    return uri.queryParameters['reference'] == widget.reference ||
        uri.queryParameters['trxref'] == widget.reference;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Paystack payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
