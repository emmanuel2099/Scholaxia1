import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class ExamChip extends StatelessWidget {
  final String label;

  const ExamChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
