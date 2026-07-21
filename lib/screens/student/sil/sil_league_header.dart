import 'package:flutter/material.dart';

import '../../../api/api_service.dart';
import 'sil_models.dart';
import 'sil_widgets.dart';

/// Shared League screen header (menu / logo / bell).
class SilLeagueHeader extends StatelessWidget {
  const SilLeagueHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: () {
            ApiService().setAppResumeMode('student');
            Navigator.pop(context);
          },
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF1F2937)),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: SilColors.purple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Scholaxia Intellect League',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded,
                  color: Color(0xFF1F2937)),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Text('3',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
