import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// Shared SIL (Aczone-exact) tokens — brand purple.
class SilColors {
  static const purple = Color(0xFF6A5AE0);
  static const purpleDeep = Color(0xFF5B21B6);
  static const purpleSoft = Color(0xFFF3E8FF);
  static const gold = Color(0xFFFBBF24);
  static const pageBg = Color(0xFFF7F7FB);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
}

/// Top bar matching Aczone: menu / logo / trailing.
class SilAczoneAppBar extends StatelessWidget {
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool light;

  const SilAczoneAppBar({
    super.key,
    this.onBack,
    this.trailing,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = light ? Colors.white : SilColors.text;
    return Row(
      children: [
        IconButton(
          onPressed: onBack ?? () => Navigator.maybePop(context),
          icon: Icon(Icons.menu_rounded, color: fg, size: 26),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: light ? Colors.white : SilColors.purple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'SL',
                  style: TextStyle(
                    color: light ? SilColors.purple : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Scholaxia',
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
        trailing ??
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.notifications_none_rounded, color: fg, size: 26),
            ),
      ],
    );
  }
}

class SilPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const SilPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: SilColors.purple,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16),
              ),
      ),
    );
  }
}

class SilCoinChip extends StatelessWidget {
  final int coins;
  const SilCoinChip({super.key, required this.coins});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SilColors.purpleSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded,
              color: SilColors.gold, size: 18),
          const SizedBox(width: 4),
          Text(
            '$coins',
            style: TextStyle(
              color: context.textColor,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class SilSectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SilSectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: SilColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action!,
                  style: const TextStyle(
                      color: SilColors.purple, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
