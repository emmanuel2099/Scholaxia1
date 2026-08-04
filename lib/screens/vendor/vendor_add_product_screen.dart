import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_service.dart';
import 'vendor_theme.dart';

class VendorAddProductScreen extends StatefulWidget {
  const VendorAddProductScreen({super.key});

  @override
  State<VendorAddProductScreen> createState() => _VendorAddProductScreenState();
}

class _VendorAddProductScreenState extends State<VendorAddProductScreen> {
  final _api = ApiService();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '1');

  static const _categories = [
    'books',
    'gadgets',
    'laptops',
    'phones',
    'clothes',
    'other',
  ];

  String _category = 'books';
  bool _available = true;
  bool _saving = false;
  bool _uploading = false;
  Uint8List? _imageBytes;
  String? _imageName;
  String? _uploadedImageUrl;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      _toast('Could not read that image. Try another file.');
      return;
    }
    setState(() {
      _imageBytes = Uint8List.fromList(file.bytes!);
      _imageName = file.name;
      _uploadedImageUrl = null;
    });
  }

  Future<String?> _ensureImageUrl() async {
    if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty) {
      return _uploadedImageUrl;
    }
    if (_imageBytes == null || _imageName == null) return null;
    setState(() => _uploading = true);
    try {
      final uploaded = await _api.communityUpload(_imageBytes!, _imageName!);
      final raw = uploaded['file_url']?.toString() ??
          uploaded['secure_url']?.toString() ??
          uploaded['url']?.toString() ??
          '';
      final url = _api.resolveMediaUrl(raw);
      if (url.isEmpty) {
        throw const ApiException.message('Upload succeeded but no image URL returned.');
      }
      _uploadedImageUrl = url;
      return url;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '')) ?? -1;
    final stock = int.tryParse(_stockCtrl.text.trim()) ?? -1;

    if (title.length < 2) {
      _toast('Enter a product title.');
      return;
    }
    if (desc.isEmpty) {
      _toast('Enter a product description for the student marketplace.');
      return;
    }
    if (price < 0) {
      _toast('Enter a valid price.');
      return;
    }
    if (stock < 0) {
      _toast('Enter a valid stock quantity.');
      return;
    }
    if (_imageBytes == null && (_uploadedImageUrl == null || _uploadedImageUrl!.isEmpty)) {
      _toast('Add a product image.');
      return;
    }

    setState(() => _saving = true);
    try {
      final imageUrl = await _ensureImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        _toast('Could not upload product image.');
        return;
      }
      await _api.vendorCreateProduct(
        title: title,
        category: _category,
        price: price,
        imageUrl: imageUrl,
        description: desc,
        stockQty: stock,
        isAvailable: _available,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product added. Students can see it in Marketplace.')),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _uploading;
    return Scaffold(
      backgroundColor: VendorTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: VendorTheme.text,
        elevation: 0,
        title: const Text(
          'Add Product',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: VendorTheme.cardDecoration(radius: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Product image',
                    style: TextStyle(
                      color: VendorTheme.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'This image shows on the student Marketplace.',
                    style: TextStyle(color: VendorTheme.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: busy ? null : _pickImage,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        color: VendorTheme.bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: VendorTheme.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _imageBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(_imageBytes!, fit: BoxFit.cover),
                                Positioned(
                                  right: 10,
                                  bottom: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: const Text(
                                      'Change image',
                                      style: TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 42, color: VendorTheme.maroon),
                                SizedBox(height: 8),
                                Text(
                                  'Tap to add product photo',
                                  style: TextStyle(
                                    color: VendorTheme.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: VendorTheme.cardDecoration(radius: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Product details',
                    style: TextStyle(
                      color: VendorTheme.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label('Title'),
                  _field(_titleCtrl, 'e.g. JAMB Past Questions Pack'),
                  const SizedBox(height: 12),
                  _label('Description (shown to students)'),
                  _field(
                    _descCtrl,
                    'Describe what students will get…',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  _label('Category'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: VendorTheme.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: VendorTheme.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _category,
                        isExpanded: true,
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c[0].toUpperCase() + c.substring(1)),
                              ),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _category = v);
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Price (₦)'),
                            _field(
                              _priceCtrl,
                              '0.00',
                              type: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Stock qty'),
                            _field(
                              _stockCtrl,
                              '1',
                              type: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: VendorTheme.maroon,
                    title: const Text(
                      'Available for students',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    value: _available,
                    onChanged: busy ? null : (v) => setState(() => _available = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: busy ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VendorTheme.maroon,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Save Product',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: VendorTheme.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType type = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: type,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: VendorTheme.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: VendorTheme.muted),
        filled: true,
        fillColor: VendorTheme.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VendorTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VendorTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VendorTheme.maroon, width: 1.4),
        ),
      ),
    );
  }
}
