import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType keyboardType;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: TextStyle(color: context.textColor, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: context.greyColor, fontSize: 15),
          prefixIcon: Icon(prefixIcon, color: context.greyColor, size: 22),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        ),
      ),
    );
  }
}
