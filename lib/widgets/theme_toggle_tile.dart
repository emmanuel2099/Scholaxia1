import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Dark / light mode switch for profile screens.
class ThemeToggleTile extends StatelessWidget {
  final Color? accentColor;

  const ThemeToggleTile({super.key, this.accentColor});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? context.accentColor;
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: accent,
          ),
          title: Text(
            isDark ? 'Light mode' : 'Dark mode',
            style: TextStyle(
              color: context.textColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            isDark ? 'Switch to a brighter theme' : 'Switch to dark theme',
            style: TextStyle(color: context.greyColor, fontSize: 12),
          ),
          trailing: Switch.adaptive(
            value: isDark,
            activeThumbColor: accent,
            onChanged: (_) => themeNotifier.toggle(),
          ),
          onTap: () => themeNotifier.toggle(),
        ),
      ),
    );
  }
}
