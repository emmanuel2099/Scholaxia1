import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_service.dart';
import 'vendor_theme.dart';

class VendorKycScreen extends StatefulWidget {
  const VendorKycScreen({super.key});

  @override
  State<VendorKycScreen> createState() => _VendorKycScreenState();
}

class _VendorKycScreenState extends State<VendorKycScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _ninCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _alreadyDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _addressCtrl.dispose();
    _ninCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final kyc = await _api.vendorGetKyc();
      if (!mounted) return;
      _nameCtrl.text = kyc['full_name']?.toString() ?? '';
      _locationCtrl.text = kyc['location']?.toString() ?? '';
      _addressCtrl.text = kyc['address']?.toString() ?? '';
      _ninCtrl.text = kyc['nin']?.toString() ?? '';
      _alreadyDone = kyc['kyc_completed'] == true;
    } catch (_) {
      // New vendors may not have KYC yet — form stays empty.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final location = _locationCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final nin = _ninCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (name.length < 2 || location.length < 2 || address.length < 5) {
      _toast('Enter your full name, location and street address.');
      return;
    }
    if (nin.length != 11) {
      _toast('NIN must be 11 digits.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.vendorSubmitKyc(
        fullName: name,
        location: location,
        address: address,
        nin: nin,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('KYC saved. You can post products now.')),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VendorTheme.bg,
      appBar: AppBar(
        backgroundColor: VendorTheme.bg,
        foregroundColor: VendorTheme.text,
        elevation: 0,
        title: const Text(
          'Vendor KYC',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: VendorTheme.maroon))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: VendorTheme.maroonSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Before posting products, verify your identity with your NIN. '
                    'This helps Scholaxia find you if a dispute happens.',
                    style: TextStyle(color: VendorTheme.text, height: 1.4),
                  ),
                ),
                if (_alreadyDone) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'KYC already completed. You can update details below if needed.',
                    style: TextStyle(color: VendorTheme.approvedFg, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 18),
                const Text('FULL NAME', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 6),
                _field(_nameCtrl, 'Name as on your NIN'),
                const SizedBox(height: 14),
                const Text('LOCATION', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 6),
                _field(_locationCtrl, 'City / State'),
                const SizedBox(height: 14),
                const Text('ADDRESS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 6),
                _field(_addressCtrl, 'Street address', maxLines: 2),
                const SizedBox(height: 14),
                const Text('NIN', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 6),
                _field(
                  _ninCtrl,
                  '11-digit National Identity Number',
                  keyboard: TextInputType.number,
                  digitsOnly: true,
                  maxLength: 11,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VendorTheme.maroon,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_alreadyDone ? 'Update KYC' : 'Submit KYC'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboard,
    int maxLines = 1,
    bool digitsOnly = false,
    int? maxLength,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      maxLength: maxLength,
      cursorColor: VendorTheme.maroon,
      style: const TextStyle(color: VendorTheme.text, fontWeight: FontWeight.w500),
      inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: VendorTheme.muted),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: VendorTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: VendorTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: VendorTheme.maroon, width: 1.5),
        ),
      ),
    );
  }
}
