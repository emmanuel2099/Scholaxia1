import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFF3A3A3A))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: TextStyle(
                color: AppColors.grey.withOpacity(0.8), fontSize: 12),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFF3A3A3A))),
      ],
    );
  }
}
