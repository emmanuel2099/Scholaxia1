class SiaBoardItem {
  final String type;
  final String content;

  const SiaBoardItem({required this.type, required this.content});

  factory SiaBoardItem.fromJson(Map<String, dynamic> json) => SiaBoardItem(
        type: json['type']?.toString() ?? 'point',
        content: json['content']?.toString() ?? '',
      );

  static List<SiaBoardItem> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => SiaBoardItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.content.trim().isNotEmpty)
        .toList();
  }
}
