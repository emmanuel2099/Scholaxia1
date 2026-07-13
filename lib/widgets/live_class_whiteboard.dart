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
      if (v != null) c = Color(0xFF000000 | v);
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

/// A typed text block placed on the whiteboard.
class BoardText {
  final String id;
  final Offset pos;
  final String text;
  final Color color;
  final double size;

  const BoardText({
    required this.id,
    required this.pos,
    required this.text,
    this.color = Colors.white,
    this.size = 20,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': pos.dx,
        'y': pos.dy,
        'text': text,
        'color': '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}',
        'size': size,
      };

  factory BoardText.fromJson(Map<String, dynamic> data) {
    Color c = Colors.white;
    final hex = data['color']?.toString();
    if (hex != null && hex.startsWith('#')) {
      final v = int.tryParse(hex.substring(1), radix: 16);
      if (v != null) c = Color(0xFF000000 | v);
    }
    return BoardText(
      id: data['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      pos: Offset(
        (data['x'] as num?)?.toDouble() ?? 24,
        (data['y'] as num?)?.toDouble() ?? 40,
      ),
      text: data['text']?.toString() ?? '',
      color: c,
      size: (data['size'] as num?)?.toDouble() ?? 20,
    );
  }
}

/// Per-subject symbol keyboards (mirrors the desktop classroom).
const Map<String, List<String>> kSubjectSymbols = {
  'English': [
    'a', 'e', 'i', 'o', 'u', 'ā', 'ē', 'ī', 'ō', 'ū',
    'ă', 'ĕ', 'ĭ', 'ŏ', 'ŭ', 'A', 'E', 'I', 'O', 'U',
    'iː', 'ɪ', 'e', 'æ', 'ɑː', 'ɒ', 'ɔː', 'ʊ', 'uː', 'ʌ',
    'ɜː', 'ə', 'eɪ', 'aɪ', 'ɔɪ', 'aʊ', 'əʊ', 'ɪə', 'eə', 'ʊə',
    '—', '–', '…', '‘', '’', '“', '”', ';', ':', '?', '!',
  ],
  'Mathematics': [
    '+', '−', '×', '÷', '=', '≠', '≈', '≤', '≥', '±', '∞', '√',
    'π', 'θ', 'α', 'β', 'Δ', '∫', '∑', '°', 'x²', 'x³', '½', '¼',
    '→', '∈', '∪', '∩', 'ℝ', 'ℕ', 'sin', 'cos', 'tan', 'log', 'ln',
    '(', ')', '[', ']', '{', '}',
  ],
  'Physics': [
    'F', 'm', 'a', 'v', 'u', 't', 'Ω', 'λ', 'Hz', 'J', 'N', 'kg',
    'm/s', 'm/s²', 'Δ', 'ρ', 'μ', 'ω', 'F=ma', 'V=IR', 'E=mc²',
    '°C', 'K', 'Pa', 'π', '±', '≈', '∝',
  ],
  'Chemistry': [
    'H', 'O', 'C', 'N', 'Na', 'Cl', 'H₂', 'O₂', 'CO₂', 'H₂O', 'NaCl',
    'H⁺', 'OH⁻', 'e⁻', '→', '⇌', '(s)', '(l)', '(g)', '(aq)', 'Δ',
    'mol', 'pH', '+', '−', '=', '²', '³', '⁺', '⁻',
  ],
  'Igbo': [
    'a', 'ch', 'gb', 'gh', 'gw', 'i', 'ị', 'kp', 'kw', 'ṅ', 'nw',
    'ny', 'o', 'ọ', 'u', 'ụ', 'á', 'à', 'é', 'è', 'í', 'ì', 'ó', 'ò',
    'ú', 'ù',
  ],
  'Yoruba': [
    'a', 'e', 'ẹ', 'gb', 'i', 'o', 'ọ', 'ṣ', 'u', 'á', 'à', 'é', 'è',
    'ẹ́', 'ẹ̀', 'í', 'ì', 'ó', 'ò', 'ọ́', 'ọ̀', 'ú', 'ù', 'ń',
  ],
  'Hausa': [
    'a', 'ɓ', 'ɗ', 'e', 'i', 'ƙ', 'o', 'sh', 'u', 'ʼ', 'á', 'à', 'é',
    'è', 'í', 'ì', 'ó', 'ò', 'ú', 'ù',
  ],
};

enum BoardTool { draw, type, erase }

const Color _kBoardBg = Color(0xFF1B4332);

/// Holds shared board state so the canvas (top) and the toolbar/keyboard
/// (bottom) can be rendered in different parts of the screen.
class BoardController extends ChangeNotifier {
  BoardController({this.onSend, this.canDraw = false});

  void Function(String action, Map<String, dynamic> data)? onSend;
  bool canDraw;

  final List<BoardStroke> strokes = [];
  final List<BoardText> texts = [];

  BoardTool tool = BoardTool.draw;
  Color penColor = Colors.white;
  String subject = 'English';

  Offset? _lastPoint;
  String? _activeTextId;
  Offset textAnchor = const Offset(24, 40);

  void setTool(BoardTool t) {
    tool = t;
    notifyListeners();
  }

  void setColor(Color c) {
    penColor = c;
    notifyListeners();
  }

  void setSubject(String s) {
    subject = s;
    notifyListeners();
  }

  static const double _eraseRadius = 24;

  // ---- Drawing ----
  void panStart(Offset p) {
    if (tool == BoardTool.type) {
      textAnchor = p;
      _activeTextId = null;
      notifyListeners();
      return;
    }
    if (tool == BoardTool.erase) {
      eraseAt(p);
      return;
    }
    _lastPoint = p;
  }

  void panUpdate(Offset p) {
    if (tool == BoardTool.type) return;
    if (tool == BoardTool.erase) {
      eraseAt(p);
      return;
    }
    final from = _lastPoint;
    if (from == null) return;
    final stroke = BoardStroke(from: from, to: p, color: penColor, width: 3);
    strokes.add(stroke);
    _lastPoint = p;
    notifyListeners();
    onSend?.call('draw', stroke.toJson());
  }

  void panEnd() => _lastPoint = null;

  /// Truly removes ink and text near [p] (instead of painting over it).
  void eraseAt(Offset p, {bool broadcast = true}) {
    final r = _eraseRadius;
    final beforeStrokes = strokes.length;
    final beforeTexts = texts.length;
    strokes.removeWhere((s) => _distToSegment(p, s.from, s.to) <= r + s.width);
    texts.removeWhere((t) => _hitsText(p, t, r));
    if (strokes.length != beforeStrokes || texts.length != beforeTexts) {
      notifyListeners();
    }
    if (broadcast && canDraw) {
      onSend?.call('erase', {'x': p.dx, 'y': p.dy, 'r': r});
    }
  }

  bool _hitsText(Offset p, BoardText t, double r) {
    // Approximate the text bounding box (top-left anchored).
    final w = (t.text.length * t.size * 0.58).clamp(t.size, 4000).toDouble();
    final h = t.size * 1.4;
    final rect = Rect.fromLTWH(t.pos.dx - r, t.pos.dy - r, w + 2 * r, h + 2 * r);
    return rect.contains(p);
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / (dx * dx + dy * dy))
        .clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  // ---- Typing ----
  void updateTypingText(String value) {
    final id = _activeTextId ??=
        DateTime.now().microsecondsSinceEpoch.toString();
    final t = BoardText(
      id: id,
      pos: textAnchor,
      text: value,
      color: penColor,
      size: 22,
    );
    final idx = texts.indexWhere((e) => e.id == id);
    if (idx == -1) {
      if (value.isNotEmpty) texts.add(t);
    } else {
      if (value.isEmpty) {
        texts.removeAt(idx);
      } else {
        texts[idx] = t;
      }
    }
    notifyListeners();
    onSend?.call('text_stream', t.toJson());
  }

  void commitText(String value) {
    final id = _activeTextId;
    if (id != null && value.trim().isNotEmpty) {
      final t = BoardText(
        id: id,
        pos: textAnchor,
        text: value,
        color: penColor,
        size: 22,
      );
      onSend?.call('text', t.toJson());
    }
    _activeTextId = null;
    textAnchor = Offset(textAnchor.dx, textAnchor.dy + 34);
    notifyListeners();
  }

  // ---- Sync / clear ----
  void handleRemoteMessage(Map<String, dynamic> msg) {
    final action = msg['action']?.toString() ?? '';
    final data = msg['data'];
    if (data is! Map) return;
    final m = Map<String, dynamic>.from(data);

    switch (action) {
      case 'draw':
        strokes.add(BoardStroke.fromJson(m));
        notifyListeners();
        break;
      case 'clear':
        strokes.clear();
        texts.clear();
        notifyListeners();
        break;
      case 'erase':
        eraseAt(
          Offset(
            (m['x'] as num?)?.toDouble() ?? 0,
            (m['y'] as num?)?.toDouble() ?? 0,
          ),
          broadcast: false,
        );
        break;
      case 'text':
      case 'text_stream':
        final t = BoardText.fromJson(m);
        final idx = texts.indexWhere((e) => e.id == t.id);
        if (t.text.trim().isEmpty) {
          if (idx != -1) texts.removeAt(idx);
        } else if (idx == -1) {
          texts.add(t);
        } else {
          texts[idx] = t;
        }
        notifyListeners();
        break;
    }
  }

  void clear({bool broadcast = true}) {
    strokes.clear();
    texts.clear();
    _activeTextId = null;
    notifyListeners();
    if (broadcast && canDraw) onSend?.call('clear', {});
  }
}

/// The drawing surface — shown at the top (video area) for everyone.
class LiveClassBoardCanvas extends StatelessWidget {
  final BoardController controller;

  const LiveClassBoardCanvas({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          color: _kBoardBg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onPanStart: controller.canDraw
                        ? (d) => controller.panStart(d.localPosition)
                        : null,
                    onPanUpdate: controller.canDraw
                        ? (d) => controller.panUpdate(d.localPosition)
                        : null,
                    onPanEnd:
                        controller.canDraw ? (_) => controller.panEnd() : null,
                    onTapDown: controller.canDraw &&
                            controller.tool == BoardTool.type
                        ? (d) => controller.panStart(d.localPosition)
                        : null,
                    child: CustomPaint(
                      painter: _BoardPainter(
                        strokes: controller.strokes,
                        texts: controller.texts,
                      ),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                  );
                },
              ),
              if (controller.canDraw && controller.tool == BoardTool.type)
                const Positioned(
                  top: 6,
                  left: 8,
                  child: Text(
                    'Tap where you want to type',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              if (!controller.canDraw)
                const Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'Teacher is presenting',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The toolbar + subject keyboard + type input — shown at the bottom.
class LiveClassBoardControls extends StatefulWidget {
  final BoardController controller;

  const LiveClassBoardControls({super.key, required this.controller});

  @override
  State<LiveClassBoardControls> createState() => _LiveClassBoardControlsState();
}

class _LiveClassBoardControlsState extends State<LiveClassBoardControls> {
  final TextEditingController _typeController = TextEditingController();

  BoardController get c => widget.controller;

  @override
  void dispose() {
    _typeController.dispose();
    super.dispose();
  }

  void _insertSymbol(String sym) {
    final sel = _typeController.selection;
    final text = _typeController.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final newText = text.replaceRange(start, end, sym);
    _typeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + sym.length),
    );
    c.updateTypingText(newText);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return Container(
          color: const Color(0xFF14261C),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _toolRow(),
              if (c.tool == BoardTool.type) ...[
                const SizedBox(height: 8),
                _subjectChips(),
                const SizedBox(height: 6),
                _symbolGrid(),
                const SizedBox(height: 8),
                _typeInput(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _toolRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _toolBtn(Icons.edit, 'Draw', BoardTool.draw),
          _toolBtn(Icons.title, 'Type', BoardTool.type),
          _toolBtn(Icons.auto_fix_high, 'Erase', BoardTool.erase),
          const SizedBox(width: 10),
          _colorBtn(Colors.white),
          _colorBtn(Colors.yellow),
          _colorBtn(Colors.red),
          _colorBtn(Colors.cyan),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => c.clear(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 15, color: Colors.white70),
                  SizedBox(width: 4),
                  Text('Clear',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, BoardTool tool) {
    final selected = c.tool == tool;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => c.setTool(tool),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white24 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? Colors.white : Colors.white24, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorBtn(Color color) {
    final selected = c.penColor == color;
    return GestureDetector(
      onTap: () => c.setColor(color),
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }

  Widget _subjectChips() {
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: kSubjectSymbols.keys.map((s) {
          final sel = s == c.subject;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => c.setSubject(s),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: sel ? Colors.white : Colors.white12,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(s,
                    style: TextStyle(
                        color: sel ? _kBoardBg : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _symbolGrid() {
    final symbols = kSubjectSymbols[c.subject] ?? const [];
    return SizedBox(
      height: 94,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 46,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: symbols.length,
        itemBuilder: (_, i) {
          final sym = symbols[i];
          return GestureDetector(
            onTap: () => _insertSymbol(sym),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(sym,
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          );
        },
      ),
    );
  }

  Widget _typeInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _typeController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onChanged: c.updateTypingText,
            onSubmitted: (v) {
              c.commitText(v);
              _typeController.clear();
            },
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Type — students see it live on the board.',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            c.commitText(_typeController.text);
            _typeController.clear();
          },
          child: const CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white24,
            child: Icon(Icons.check, color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }
}

class _BoardPainter extends CustomPainter {
  final List<BoardStroke> strokes;
  final List<BoardText> texts;

  _BoardPainter({required this.strokes, required this.texts});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _kBoardBg,
    );
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(s.from, s.to, paint);
    }
    for (final t in texts) {
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: t.color,
            fontSize: t.size,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: (size.width - t.pos.dx - 8).clamp(20, size.width));
      tp.paint(canvas, t.pos);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}
