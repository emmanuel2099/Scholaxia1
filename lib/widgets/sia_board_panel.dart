import 'package:flutter/material.dart';

import '../models/sia_board_item.dart';
import '../theme/app_theme.dart';

/// Learning board — key points, steps, formulas (purple Scholaxia theme).
class SiaBoardPanel extends StatelessWidget {
  final List<SiaBoardItem> items;
  final VoidCallback? onClose;
  final bool embedded;
  final bool purpleTheme;
  final ScrollController? scrollController;

  const SiaBoardPanel({
    super.key,
    required this.items,
    this.onClose,
    this.embedded = false,
    this.purpleTheme = false,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final list = ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _BoardRow(item: items[i], purple: purpleTheme),
    );

    if (embedded) {
      return list;
    }

    final headerBg = purpleTheme ? const Color(0xFF2E1065) : const Color(0xFF1E3A1E);
    final border = purpleTheme ? const Color(0xFF4C1D95) : const Color(0xFF2A4A2A);
    final accent = purpleTheme ? AppColors.primaryDark : const Color(0xFF7DBA7D);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: purpleTheme ? AppColors.cardBg : const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded, color: accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sia Board — key points',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (onClose != null)
                  GestureDetector(
                    onTap: onClose,
                    child: Icon(Icons.close_rounded, color: accent, size: 18),
                  ),
              ],
            ),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  final SiaBoardItem item;
  final bool purple;

  const _BoardRow({required this.item, this.purple = false});

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
    if (purple) {
      switch (type) {
        case 'heading':
          return _BoardStyle(
            color: AppColors.greyLight,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.primaryDark, width: 3)),
            ),
            padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
          );
        case 'formula':
        case 'equation':
          return _BoardStyle(
            color: const Color(0xFFFDE68A),
            fontSize: 14,
            mono: true,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.primary.withOpacity(0.4)),
            ),
            padding: const EdgeInsets.all(10),
          );
        default:
          return _BoardStyle(
            color: AppColors.white,
            fontSize: 13,
            icon: Icons.fiber_manual_record,
          );
      }
    }

    switch (type) {
      case 'heading':
        return _BoardStyle(
          color: const Color(0xFFA8E6A8),
          fontWeight: FontWeight.w700,
          fontSize: 14,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFF4CAF50), width: 3)),
          ),
          padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
        );
      case 'step':
        return _BoardStyle(
          color: const Color(0xFFE8F5E8),
          fontSize: 13,
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A1E),
            borderRadius: BorderRadius.circular(6),
            border: const Border(left: BorderSide(color: Color(0xFF2196F3), width: 3)),
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
            color: const Color(0xFF2A2A1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF5A5A2A)),
          ),
          padding: const EdgeInsets.all(10),
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
