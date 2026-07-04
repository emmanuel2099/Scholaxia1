import 'package:flutter/material.dart';

/// A draw stroke on the live class whiteboard.
class BoardStroke {
  final Offset from;
  final Offset to;
  final Color color;
  final double width;

  const BoardStroke({
    required this.from,
    required this.to,
    this.color = Colors.white,
    this.width = 3,
  });

  Map<String, dynamic> toJson() => {
        'x0': from.dx,
        'y0': from.dy,
        'x1': to.dx,
        'y1': to.dy,
        'color': '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
        'width': width,
      };

  factory BoardStroke.fromJson(Map<String, dynamic> data) {
    Color c = Colors.white;
    final hex = data['color']?.toString();
    if (hex != null && hex.startsWith('#')) {
      final v = int.tryParse(hex.substring(1), radix: 16);
      if (v != null) c = Color(v);
    }
    return BoardStroke(
      from: Offset(
        (data['x0'] as num?)?.toDouble() ?? 0,
        (data['y0'] as num?)?.toDouble() ?? 0,
      ),
      to: Offset(
        (data['x1'] as num?)?.toDouble() ?? 0,
        (data['y1'] as num?)?.toDouble() ?? 0,
      ),
      color: c,
      width: (data['width'] as num?)?.toDouble() ?? 3,
    );
  }
}

class LiveClassWhiteboard extends StatefulWidget {
  final bool canDraw;
  final void Function(String action, Map<String, dynamic> data)? onSend;

  const LiveClassWhiteboard({
    super.key,
    required this.canDraw,
    this.onSend,
  });

  @override
  State<LiveClassWhiteboard> createState() => LiveClassWhiteboardState();
}

class LiveClassWhiteboardState extends State<LiveClassWhiteboard> {
  final List<BoardStroke> _strokes = [];
  Offset? _lastPoint;
  Color _penColor = Colors.white;

  void handleRemoteMessage(Map<String, dynamic> msg) {
    final action = msg['action']?.toString() ?? '';
    final data = msg['data'];
    if (data is! Map) return;
    final m = Map<String, dynamic>.from(data);

    switch (action) {
      case 'draw':
        setState(() => _strokes.add(BoardStroke.fromJson(m)));
        break;
      case 'clear':
        setState(() => _strokes.clear());
        break;
    }
  }

  void clearBoard({bool broadcast = true}) {
    setState(() => _strokes.clear());
    if (broadcast && widget.canDraw) {
      widget.onSend?.call('clear', {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B4332),
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onPanStart: widget.canDraw
                    ? (d) => _lastPoint = d.localPosition
                    : null,
                onPanUpdate: widget.canDraw
                    ? (d) {
                        final from = _lastPoint;
                        if (from == null) return;
                        final to = d.localPosition;
                        final stroke = BoardStroke(
                          from: from,
                          to: to,
                          color: _penColor,
                        );
                        setState(() {
                          _strokes.add(stroke);
                          _lastPoint = to;
                        });
                        widget.onSend?.call('draw', stroke.toJson());
                      }
                    : null,
                onPanEnd: widget.canDraw ? (_) => _lastPoint = null : null,
                child: CustomPaint(
                  painter: _BoardPainter(strokes: _strokes),
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              );
            },
          ),
          if (widget.canDraw)
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  _colorBtn(Colors.white),
                  _colorBtn(Colors.yellow),
                  _colorBtn(Colors.red),
                  _colorBtn(Colors.cyan),
                  IconButton(
                    onPressed: () => clearBoard(),
                    icon: const Icon(Icons.delete_outline, color: Colors.white70),
                    tooltip: 'Clear board',
                  ),
                ],
              ),
            ),
          if (!widget.canDraw)
            const Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'View only — teacher is presenting',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _colorBtn(Color c) {
    final selected = _penColor == c;
    return GestureDetector(
      onTap: () => setState(() => _penColor = c),
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final List<BoardStroke> strokes;

  _BoardPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1B4332),
    );
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(s.from, s.to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) =>
      oldDelegate.strokes.length != strokes.length;
}
