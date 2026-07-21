import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_windows/webview_windows.dart' as windows;

import '../api/api_service.dart';
import 'offline_status_service.dart';

class PaystackCheckoutService {
  PaystackCheckoutService._();

  static Future<bool> purchase({
    required BuildContext context,
    required ApiService api,
    required String productType,
    required String productId,
  }) async {
    if (OfflineStatusService.instance.isOffline.value) {
      throw const ApiException.message(
        'Payment requires internet data. Connect and try again.',
      );
    }
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

    if (!context.mounted) return false;

    bool shouldVerify;
    if (Platform.isWindows) {
      shouldVerify =
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _WindowsPaystackCheckout(
                authorizationUrl: url,
                reference: reference,
              ),
            ),
          ) ??
          false;
    } else if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      shouldVerify =
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _MobilePaystackCheckout(
                authorizationUrl: url,
                reference: reference,
              ),
            ),
          ) ??
          false;
    } else {
      // Only unsupported desktop platforms fall back to a browser.
      shouldVerify = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.inAppBrowserView,
      );
    }

    if (!shouldVerify) return false;
    final result = await api.verifyPaystack(reference);
    return result['paid'] == true || result['has_access'] == true;
  }
}

bool _isPaymentCallback(String raw, String reference) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return false;
  if (uri.host == 'scholaxia.app' &&
      uri.path.startsWith('/paystack/callback')) {
    return true;
  }
  return uri.queryParameters['reference'] == reference ||
      uri.queryParameters['trxref'] == reference;
}

class _MobilePaystackCheckout extends StatefulWidget {
  const _MobilePaystackCheckout({
    required this.authorizationUrl,
    required this.reference,
  });

  final String authorizationUrl;
  final String reference;

  @override
  State<_MobilePaystackCheckout> createState() =>
      _MobilePaystackCheckoutState();
}

class _MobilePaystackCheckoutState extends State<_MobilePaystackCheckout> {
  late final mobile.WebViewController _controller;
  bool _loading = true;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onPageStarted: (url) {
            if (_complete(url)) return;
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            if (_complete(request.url)) {
              return mobile.NavigationDecision.prevent;
            }
            return mobile.NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  bool _complete(String url) {
    if (_closing || !_isPaymentCallback(url, widget.reference)) return false;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, true);
    });
    return true;
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
          mobile.WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _WindowsPaystackCheckout extends StatefulWidget {
  const _WindowsPaystackCheckout({
    required this.authorizationUrl,
    required this.reference,
  });

  final String authorizationUrl;
  final String reference;

  @override
  State<_WindowsPaystackCheckout> createState() =>
      _WindowsPaystackCheckoutState();
}

class _WindowsPaystackCheckoutState extends State<_WindowsPaystackCheckout> {
  final windows.WebviewController _controller = windows.WebviewController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _error;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      _subscriptions.add(
        _controller.url.listen((url) {
          if (_closing ||
              !_isPaymentCallback(url, widget.reference) ||
              !mounted) {
            return;
          }
          _closing = true;
          Navigator.pop(context, true);
        }),
      );
      await _controller.setPopupWindowPolicy(
        windows.WebviewPopupWindowPolicy.deny,
      );
      await _controller.loadUrl(widget.authorizationUrl);
      if (mounted) setState(() {});
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error =
              error.message ??
              'Microsoft Edge WebView2 is required for in-app payment.';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _controller.dispose();
    super.dispose();
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
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : !_controller.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                windows.Webview(_controller),
                StreamBuilder<windows.LoadingState>(
                  stream: _controller.loadingState,
                  builder: (_, snapshot) =>
                      snapshot.data == windows.LoadingState.loading
                      ? const LinearProgressIndicator()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
    );
  }
}
