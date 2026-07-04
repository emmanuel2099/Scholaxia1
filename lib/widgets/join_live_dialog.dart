import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Paste access code to join a live class (desktop join-access-modal).
Future<String?> showJoinLiveCodeDialog(
  BuildContext context, {
  String? initialCode,
}) async {
  final controller = TextEditingController(text: initialCode ?? '');

  final code = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: ctx.cardColor,
        title: Text(
          'Join live class',
          style: TextStyle(
            color: ctx.textColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste the access code from the popup when your class went live.',
              style: TextStyle(color: ctx.greyColor, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                color: ctx.textColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. SX-A1B2C3D4',
                hintStyle: TextStyle(color: ctx.greyColor.withOpacity(0.7)),
                filled: true,
                fillColor: ctx.surfColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: ctx.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: ctx.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: ctx.accentColor, width: 2),
                ),
              ),
              onSubmitted: (v) {
                final trimmed = v.trim();
                if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed.toUpperCase());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ctx.greyColor)),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.pop(ctx, trimmed.toUpperCase());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ctx.accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Enter class'),
          ),
        ],
      );
    },
  );

  controller.dispose();
  return code;
}
