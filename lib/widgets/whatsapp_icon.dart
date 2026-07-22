import 'package:flutter/material.dart';

/// Official WhatsApp logo mark (green bubble + white phone).
class WhatsAppIcon extends StatelessWidget {
  const WhatsAppIcon({
    super.key,
    this.size = 24,
    this.color = Colors.white,
    this.backgroundColor = const Color(0xFF25D366),
  });

  final double size;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WhatsAppPainter(
          foreground: color,
          background: backgroundColor,
        ),
      ),
    );
  }
}

class _WhatsAppPainter extends CustomPainter {
  _WhatsAppPainter({required this.foreground, required this.background});

  final Color foreground;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    canvas.scale(sx, sy);

    final bg = Paint()
      ..color = background
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Green chat bubble.
    final bubble = Path()
      ..moveTo(12.04, 2)
      ..cubicTo(6.58, 2, 2.13, 6.45, 2.13, 11.91)
      ..cubicTo(2.13, 13.8, 2.62, 15.64, 3.55, 17.26)
      ..lineTo(2, 22)
      ..lineTo(6.89, 20.49)
      ..cubicTo(8.45, 21.34, 10.21, 21.8, 12.04, 21.8)
      ..cubicTo(17.5, 21.8, 21.95, 17.35, 21.95, 11.89)
      ..cubicTo(21.95, 6.45, 17.5, 2, 12.04, 2)
      ..close();
    canvas.drawPath(bubble, bg);

    final fg = Paint()
      ..color = foreground
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // White phone handset glyph.
    final phone = Path()
      ..moveTo(17.47, 14.38)
      ..cubicTo(17.2, 14.24, 15.87, 13.59, 15.62, 13.5)
      ..cubicTo(15.37, 13.41, 15.19, 13.36, 15.01, 13.64)
      ..cubicTo(14.83, 13.91, 14.31, 14.52, 14.15, 14.7)
      ..cubicTo(13.99, 14.88, 13.83, 14.9, 13.56, 14.77)
      ..cubicTo(13.29, 14.63, 12.42, 14.35, 11.39, 13.43)
      ..cubicTo(10.59, 12.72, 10.05, 11.84, 9.89, 11.57)
      ..cubicTo(9.73, 11.3, 9.87, 11.16, 10.01, 11.02)
      ..cubicTo(10.13, 10.9, 10.28, 10.7, 10.42, 10.54)
      ..cubicTo(10.56, 10.38, 10.6, 10.27, 10.69, 10.09)
      ..cubicTo(10.78, 9.91, 10.74, 9.75, 10.67, 9.61)
      ..cubicTo(10.6, 9.47, 10.06, 8.14, 9.83, 7.6)
      ..cubicTo(9.61, 7.07, 9.38, 7.14, 9.22, 7.13)
      ..lineTo(8.7, 7.13)
      ..cubicTo(8.52, 7.13, 8.22, 7.2, 7.97, 7.47)
      ..cubicTo(7.72, 7.74, 7.01, 8.41, 7.01, 9.76)
      ..cubicTo(7.01, 11.11, 7.99, 12.42, 8.13, 12.6)
      ..cubicTo(8.27, 12.78, 10.06, 15.55, 12.81, 16.73)
      ..cubicTo(13.46, 17.01, 13.97, 17.18, 14.37, 17.31)
      ..cubicTo(15.03, 17.52, 15.63, 17.49, 16.1, 17.42)
      ..cubicTo(16.63, 17.34, 17.7, 16.77, 17.93, 16.14)
      ..cubicTo(18.16, 15.51, 18.16, 14.97, 18.09, 14.86)
      ..cubicTo(18.02, 14.75, 17.84, 14.68, 17.47, 14.38)
      ..close();
    canvas.drawPath(phone, fg);
  }

  @override
  bool shouldRepaint(covariant _WhatsAppPainter oldDelegate) =>
      oldDelegate.foreground != foreground ||
      oldDelegate.background != background;
}
