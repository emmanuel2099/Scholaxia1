import 'package:flutter/material.dart';

import '../models/sia_board_item.dart';

/// ChatGPT-style learning board — key points, steps, formulas from Sia's answer.
class SiaBoardPanel extends StatelessWidget {
  final List<SiaBoardItem> items;
  final VoidCallback? onClose;

  const SiaBoardPanel({
    super.key,
    required this.items,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A4A2A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E3A1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Color(0xFF2A4A2A))),
            ),
            child: Row(
              children: [
                const Icon(Icons.menu_book_rounded, color: Color(0xFF7DBA7D), size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Sia Board — key points',
                    style: TextStyle(
                      color: Color(0xFF7DBA7D),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (onClose != null)
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close_rounded, color: Color(0xFF7DBA7D), size: 18),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _BoardRow(item: items[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  final SiaBoardItem item;

  const _BoardRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(item.type);
    return Container(
      padding: style.padding,
      decoration: style.decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (style.icon != null) ...[
            Icon(style.icon, size: 14, color: style.color),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              item.content,
              style: TextStyle(
                color: style.color,
                fontSize: style.fontSize,
                height: 1.45,
                fontWeight: style.fontWeight,
                fontStyle: style.fontStyle,
                fontFamily: style.mono ? 'Courier New' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _BoardStyle _styleFor(String type) {
    switch (type) {
      case 'heading':
        return _BoardStyle(
          color: const Color(0xFFA8E6A8),
          fontWeight: FontWeight.w700,
          fontSize: 14,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFF4CAF50), width: 3)),
          ),
          padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
        );
      case 'step':
        return _BoardStyle(
          color: const Color(0xFFE8F5E8),
          fontSize: 13,
          decoration: BoxDecoration(
            color: Color(0xFF1E3A1E),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: Color(0xFF2196F3), width: 3)),
          ),
          padding: const EdgeInsets.all(8),
        );
      case 'formula':
      case 'equation':
        return _BoardStyle(
          color: const Color(0xFFFFF9C4),
          fontSize: 14,
          mono: true,
          decoration: BoxDecoration(
            color: Color(0xFF2A2A1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Color(0xFF5A5A2A)),
          ),
          padding: const EdgeInsets.all(10),
        );
      case 'example':
        return _BoardStyle(
          color: const Color(0xFFE8F5E8),
          fontSize: 13,
          icon: Icons.lightbulb_outline_rounded,
        );
      case 'diagram_hint':
        return _BoardStyle(
          color: const Color(0xFFB3E5FC),
          fontSize: 12,
          fontStyle: FontStyle.italic,
          icon: Icons.image_outlined,
        );
      default:
        return _BoardStyle(
          color: const Color(0xFFC8E6C8),
          fontSize: 13,
          icon: Icons.circle,
        );
    }
  }
}

class _BoardStyle {
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final BoxDecoration? decoration;
  final EdgeInsetsGeometry padding;
  final IconData? icon;
  final bool mono;

  const _BoardStyle({
    required this.color,
    this.fontSize = 13,
    this.fontWeight = FontWeight.normal,
    this.fontStyle = FontStyle.normal,
    this.decoration,
    this.padding = EdgeInsets.zero,
    this.icon,
    this.mono = false,
  });
}
