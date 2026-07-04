import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Popup when a teacher hosts a live class — copy the code, then dismiss.
Future<void> showAccessCodePopup(
  BuildContext context,
  Map<String, dynamic> code,
) async {
  final joinCode = code['join_code']?.toString() ?? '';
  final title = code['title']?.toString() ?? 'Live Class';
  final subject = code['subject']?.toString() ?? '';
  final teacher = code['teacher_name']?.toString() ?? 'Teacher';

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: ctx.cardColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppGradients.hero(ctx),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Class is live!',
                style: TextStyle(
                  color: ctx.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: ctx.textColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subject.isNotEmpty || teacher.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [subject, teacher].where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(color: ctx.greyColor, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Your access code',
              style: TextStyle(color: ctx.greyColor, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: ctx.accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ctx.accentColor.withOpacity(0.35)),
              ),
              child: Text(
                joinCode,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ctx.accentColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Copy this code, then tap Join Live and paste it to enter the class.',
              style: TextStyle(color: ctx.greyColor, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: joinCode));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ctx.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
