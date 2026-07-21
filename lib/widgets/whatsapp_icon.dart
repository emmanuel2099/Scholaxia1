import 'package:flutter/material.dart';

/// WhatsApp logo mark drawn locally (no extra package).
class WhatsAppIcon extends StatelessWidget {
  const WhatsAppIcon({
    super.key,
    this.size = 24,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WhatsAppPainter(color)),
    );
  }
}

class _WhatsAppPainter extends CustomPainter {
  _WhatsAppPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Scaled from a 24x24 WhatsApp-style glyph.
    final sx = size.width / 24;
    final sy = size.height / 24;
    canvas.scale(sx, sy);

    final path = Path()
      ..moveTo(12, 2.2)
      ..cubicTo(6.7, 2.2, 2.4, 6.5, 2.4, 11.8)
      ..cubicTo(2.4, 13.6, 2.9, 15.3, 3.7, 16.7)
      ..lineTo(2.2, 21.8)
      ..lineTo(7.4, 20.4)
      ..cubicTo(8.8, 21.1, 10.4, 21.5, 12, 21.5)
      ..cubicTo(17.3, 21.5, 21.6, 17.2, 21.6, 11.9)
      ..cubicTo(21.6, 6.6, 17.3, 2.2, 12, 2.2)
      ..close()
      ..moveTo(12, 19.7)
      ..cubicTo(10.6, 19.7, 9.2, 19.3, 8, 18.7)
      ..lineTo(7.7, 18.5)
      ..lineTo(4.8, 19.3)
      ..lineTo(5.6, 16.5)
      ..lineTo(5.4, 16.2)
      ..cubicTo(4.7, 14.9, 4.3, 13.4, 4.3, 11.9)
      ..cubicTo(4.3, 7.6, 7.8, 4.1, 12.1, 4.1)
      ..cubicTo(16.4, 4.1, 19.9, 7.6, 19.9, 11.9)
      ..cubicTo(19.9, 16.2, 16.3, 19.7, 12, 19.7)
      ..close()
      ..moveTo(16.5, 14.5)
      ..cubicTo(16.3, 14.4, 15.3, 13.9, 15.1, 13.8)
      ..cubicTo(14.9, 13.7, 14.8, 13.7, 14.6, 13.9)
      ..cubicTo(14.5, 14.1, 14.1, 14.5, 14, 14.6)
      ..cubicTo(13.9, 14.8, 13.7, 14.8, 13.5, 14.7)
      ..cubicTo(13.3, 14.6, 12.6, 14.4, 11.8, 13.7)
      ..cubicTo(11.2, 13.1, 10.7, 12.4, 10.6, 12.2)
      ..cubicTo(10.5, 12, 10.6, 11.9, 10.7, 11.7)
      ..cubicTo(10.8, 11.6, 10.9, 11.5, 11, 11.4)
      ..cubicTo(11.1, 11.3, 11.1, 11.2, 11.2, 11.1)
      ..cubicTo(11.3, 11, 11.2, 10.9, 11.2, 10.8)
      ..cubicTo(11.1, 10.7, 10.7, 9.7, 10.6, 9.3)
      ..cubicTo(10.4, 8.9, 10.3, 9, 10.2, 9)
      ..cubicTo(10.1, 9, 9.9, 9, 9.8, 9)
      ..cubicTo(9.6, 9, 9.4, 9.1, 9.3, 9.3)
      ..cubicTo(9.1, 9.5, 8.7, 9.9, 8.7, 10.7)
      ..cubicTo(8.7, 11.5, 9.3, 12.3, 9.4, 12.4)
      ..cubicTo(9.5, 12.6, 10.6, 14.4, 12.3, 15.1)
      ..cubicTo(12.7, 15.3, 13, 15.4, 13.3, 15.5)
      ..cubicTo(13.7, 15.6, 14.1, 15.6, 14.4, 15.6)
      ..cubicTo(14.7, 15.5, 15.5, 15.1, 15.7, 14.6)
      ..cubicTo(15.9, 14.1, 15.9, 13.7, 15.8, 13.6)
      ..cubicTo(15.7, 13.6, 15.6, 13.5, 16.5, 14.5)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhatsAppPainter oldDelegate) =>
      oldDelegate.color != color;
}
