import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_windows/webview_windows.dart' as windows;

import '../api/api_service.dart';
import 'offline_status_service.dart';

/// Opens Flutterwave inline checkout (skills enrollment) then verifies on the server.
class FlutterwaveCheckoutService {
  FlutterwaveCheckoutService._();

  static Future<bool> paySkillEnrollment({
    required BuildContext context,
    required ApiService api,
    required String skillId,
    required Map<String, dynamic> initPayload,
  }) async {
    if (OfflineStatusService.instance.isOffline.value) {
      throw const ApiException.message(
        'Payment requires internet data. Connect and try again.',
      );
    }

    final init = await api.initSkillEnrollment(
      skillId,
      fullName: (initPayload['full_name'] ?? '').toString(),
      phone: (initPayload['phone'] ?? '').toString(),
      email: initPayload['email']?.toString(),
      location: initPayload['location']?.toString(),
      preferredStart: initPayload['preferred_start']?.toString(),
      notes: initPayload['notes']?.toString(),
      paymentMode: (initPayload['payment_mode'] ?? 'half').toString(),
      installment: int.tryParse('${initPayload['installment'] ?? 1}') ?? 1,
    );

    if (init['already_paid'] == true) return true;

    final publicKey = init['public_key']?.toString() ?? '';
    final txRef = init['tx_ref']?.toString() ?? '';
    final amount = init['amount'];
    final customer = (init['customer'] is Map)
        ? Map<String, dynamic>.from(init['customer'] as Map)
        : <String, dynamic>{};
    if (publicKey.isEmpty || txRef.isEmpty) {
      throw const ApiException.message('Payment could not be started.');
    }

    if (!context.mounted) return false;

    final html = _checkoutHtml(
      publicKey: publicKey,
      txRef: txRef,
      amount: amount,
      email: customer['email']?.toString() ?? 'student@scholaxia.local',
      name: customer['name']?.toString() ?? 'Student',
      title: init['program_title']?.toString() ?? 'Skills Training',
      description: init['mode_label']?.toString() ?? 'Enrollment',
    );

    final paidResult = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _FlutterwaveCheckoutPage(html: html),
          ),
        ) ??
        {};

    if (paidResult['ok'] != true) return false;
    final transactionId =
        (paidResult['transaction_id']?.toString().isNotEmpty == true)
            ? paidResult['transaction_id'].toString()
            : txRef;

    final verified = await api.verifyFlutterwaveSkill(
      transactionId: transactionId,
      skillId: skillId,
      txRef: txRef,
    );
    return verified['paid'] == true || verified['enrollment'] == true;
  }

  static String _checkoutHtml({
    required String publicKey,
    required String txRef,
    required Object? amount,
    required String email,
    required String name,
    required String title,
    required String description,
  }) {
    final payload = jsonEncode({
      'public_key': publicKey,
      'tx_ref': txRef,
      'amount': amount,
      'currency': 'NGN',
      'payment_options': 'card,banktransfer,ussd',
      'customer': {'email': email, 'name': name},
      'customizations': {
        'title': title,
        'description': description,
      },
    });
    return '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1" />
<script src="https://checkout.flutterwave.com/v3.js"></script>
</head><body style="font-family:sans-serif;padding:24px;text-align:center">
<p>Opening Flutterwave…</p>
<script>
  const cfg = $payload;
  function done(ok) {
    if (window.ScholaxiaBridge && window.ScholaxiaBridge.postMessage) {
      window.ScholaxiaBridge.postMessage(ok ? 'success' : 'closed');
    } else {
      window.location.href = ok ? 'scholaxia://fw-success' : 'scholaxia://fw-closed';
    }
  }
  document.addEventListener('DOMContentLoaded', function () {
    FlutterwaveCheckout({
      ...cfg,
      callback: function (response) {
        const id = (response && (response.transaction_id || response.id)) || '';
        if (window.ScholaxiaBridge && window.ScholaxiaBridge.postMessage) {
          window.ScholaxiaBridge.postMessage('success:' + id);
        } else {
          window.location.href = 'scholaxia://fw-success?transaction_id=' + encodeURIComponent(id);
        }
      },
      onclose: function () {
        if (window.ScholaxiaBridge && window.ScholaxiaBridge.postMessage) {
          window.ScholaxiaBridge.postMessage('closed');
        } else {
          window.location.href = 'scholaxia://fw-closed';
        }
      },
    });
  });
</script>
</body></html>
''';
  }
}

class _FlutterwaveCheckoutPage extends StatefulWidget {
  const _FlutterwaveCheckoutPage({required this.html});
  final String html;

  @override
  State<_FlutterwaveCheckoutPage> createState() =>
      _FlutterwaveCheckoutPageState();
}

class _FlutterwaveCheckoutPageState extends State<_FlutterwaveCheckoutPage> {
  windows.WebviewController? _win;
  mobile.WebViewController? _mobile;
  bool _done = false;

  void _finish(bool ok, [String transactionId = '']) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.pop(context, {'ok': ok, 'transaction_id': transactionId});
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _initWindows();
    } else {
      _mobile = mobile.WebViewController()
        ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'ScholaxiaBridge',
          onMessageReceived: (msg) {
            final raw = msg.message;
            if (raw.startsWith('success')) {
              final id = raw.contains(':') ? raw.split(':').skip(1).join(':') : '';
              _finish(true, id);
            } else {
              _finish(false);
            }
          },
        )
        ..setNavigationDelegate(
          mobile.NavigationDelegate(
            onNavigationRequest: (req) {
              final url = req.url;
              if (url.contains('fw-success')) {
                final uri = Uri.tryParse(url);
                _finish(true, uri?.queryParameters['transaction_id'] ?? '');
                return mobile.NavigationDecision.prevent;
              }
              if (url.contains('fw-closed')) {
                _finish(false);
                return mobile.NavigationDecision.prevent;
              }
              return mobile.NavigationDecision.navigate;
            },
          ),
        )
        ..loadHtmlString(widget.html);
    }
  }

  Future<void> _initWindows() async {
    final c = windows.WebviewController();
    await c.initialize();
    c.url.listen((url) {
      if (url.contains('fw-success')) {
        final uri = Uri.tryParse(url);
        _finish(true, uri?.queryParameters['transaction_id'] ?? '');
      }
      if (url.contains('fw-closed')) _finish(false);
    });
    await c.loadStringContent(widget.html);
    if (mounted) setState(() => _win = c);
  }

  @override
  void dispose() {
    _win?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _finish(false),
        ),
      ),
      body: Platform.isWindows
          ? (_win == null
              ? const Center(child: CircularProgressIndicator())
              : windows.Webview(_win!))
          : mobile.WebViewWidget(controller: _mobile!),
    );
  }
}
