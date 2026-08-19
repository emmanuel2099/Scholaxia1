import 'dart:convert';

String formatMarketplaceNaira(num amount) {
  final n = amount.toDouble();
  if (n <= 0) return 'Ask price';
  final s = n.toStringAsFixed(0);
  final buf = StringBuffer('\u20A6');
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    buf.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  return buf.toString();
}

Map<String, dynamic> parseMarketplaceMeta(String? description) {
  final raw = description ?? '';
  final match = RegExp(r'\n*---\nSIA_META:(\{[\s\S]*?\})\s*$').firstMatch(raw);
  Map<String, dynamic> meta = {};
  if (match != null) {
    try {
      final data = jsonDecode(match.group(1)!);
      if (data is Map) meta = Map<String, dynamic>.from(data);
    } catch (_) {}
  }
  return {
    'meta': meta,
    'description': raw.replaceFirst(RegExp(r'\n*---\nSIA_META:(\{[\s\S]*?\})\s*$'), '').trim(),
  };
}

List<String> marketplaceProductImages(
  Map<String, dynamic> product,
  String Function(String) resolve,
) {
  final parsed = parseMarketplaceMeta(product['description']?.toString());
  final meta = parsed['meta'] as Map<String, dynamic>? ?? {};
  final out = <String>[];
  final extra = meta['images'];
  if (extra is List) {
    for (final u in extra) {
      final url = resolve(u.toString());
      if (url.isNotEmpty) out.add(url);
    }
  }
  final cover = product['image_url']?.toString() ?? '';
  if (cover.isNotEmpty) {
    final url = resolve(cover);
    if (url.isNotEmpty) out.insert(0, url);
  }
  final seen = <String>{};
  return out.where(seen.add).toList();
}
