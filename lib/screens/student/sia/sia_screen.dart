import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';

class SiaScreen extends StatefulWidget {
  const SiaScreen({super.key});
  @override
  State<SiaScreen> createState() => _SiaScreenState();
}

class _SiaScreenState extends State<SiaScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _api = ApiService();
  String _subject = 'Physics';
  final _subjects = ['Physics', 'Mathematics', 'Biology', 'Chemistry', 'English'];
  bool _loading = false;
  final List<_Msg> _messages = [
    const _Msg(isAi: true, text: "Hi! I'm Sia, your AI tutor. Ask me anything about your subjects — JAMB, WAEC, NECO and more.", time: '09:00 AM'),
  ];

  @override
  void dispose() { _inputCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;
    final now = _now();
    setState(() {
      _messages.add(_Msg(isAi: false, text: text, time: now));
      _inputCtrl.clear();
      _loading = true;
    });
    try {
      final r = await _api.siaAsk(question: text, subject: _subject);
      if (mounted) setState(() {
        _messages.add(_Msg(isAi: true, text: r.sia, time: _now()));
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _messages.add(_Msg(isAi: true, text: 'Sorry, I ran into an issue: ${e.message}', time: _now()));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _messages.add(_Msg(isAi: true, text: 'Something went wrong. Please try again.', time: _now()));
        _loading = false;
      });
    }
  }

  String _now() {
    final n = DateTime.now();
    final h = n.hour % 12 == 0 ? 12 : n.hour % 12;
    final m = n.minute.toString().padLeft(2, '0');
    final ampm = n.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          Expanded(child: _buildMessages(context)),
          if (_loading) _buildThinking(context),
          _buildQuickChips(context),
          _buildInput(context),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.headerColor,
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: context.accentColor, borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.bolt, color: context.isDark ? AppColors.background : Colors.white, size: 20)),
        const SizedBox(width: 10),
        Text('Sia AI Tutor', style: TextStyle(color: context.textColor, fontSize: 17, fontWeight: FontWeight.bold)),
        const Spacer(),
      ]),
    );
  }

  Widget _buildMessages(BuildContext context) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        return m.isAi ? _aiMsg(context, m) : _userMsg(context, m);
      },
    );
  }

  Widget _aiMsg(BuildContext context, _Msg m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 30, height: 30,
          decoration: BoxDecoration(color: context.accentColor, shape: BoxShape.circle),
          child: Icon(Icons.bolt, color: context.isDark ? AppColors.background : Colors.white, size: 16)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Sia AI Tutor', style: TextStyle(color: context.textColor, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Icon(Icons.bolt, color: context.accentColor, size: 12),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              border: Border.all(color: context.borderColor),
            ),
            child: Text(m.text, style: TextStyle(color: context.textColor, fontSize: 14, height: 1.5)),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Text(m.time, style: TextStyle(color: context.greyColor, fontSize: 10)),
            const SizedBox(width: 8),
            Icon(Icons.thumb_up_outlined, size: 14, color: context.greyColor),
            const SizedBox(width: 8),
            Icon(Icons.thumb_down_outlined, size: 14, color: context.greyColor),
          ]),
        ])),
        const SizedBox(width: 40),
      ]),
    );
  }

  Widget _userMsg(BuildContext context, _Msg m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 40),
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.accentColor,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12), bottomLeft: Radius.circular(12)),
            ),
            child: Text(m.text, style: TextStyle(color: context.isDark ? AppColors.background : Colors.white, fontSize: 14, height: 1.5)),
          ),
          const SizedBox(height: 4),
          Text(m.time, style: TextStyle(color: context.greyColor, fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _buildThinking(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        const SizedBox(width: 38),
        Text('••• Sia is thinking...', style: TextStyle(color: context.greyColor, fontSize: 12)),
      ]),
    );
  }

  Widget _buildQuickChips(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: [
        _chip(context, '⚡ Explain simply', () { _inputCtrl.text = 'Explain this simply'; }),
        const SizedBox(width: 8),
        _chip(context, '✓ Solve Physics problem', () { _inputCtrl.text = 'Solve this Physics problem'; }),
      ]),
    );
  }

  Widget _chip(BuildContext context, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
        ),
        child: Text(label, style: TextStyle(color: context.textColor, fontSize: 13)),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: context.headerColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: context.surfColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: context.borderColor)),
              child: Icon(Icons.history, size: 16, color: context.greyColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: context.surfColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: context.borderColor)),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: TextStyle(color: context.textColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ask Sia anything...',
                        hintStyle: TextStyle(color: context.greyColor),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _loading ? null : _send,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _loading ? context.accentColor.withOpacity(0.5) : context.accentColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.send_rounded, color: context.isDark ? AppColors.background : Colors.white, size: 18),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Sia AI can provide specialized guidance for JAMB, WAEC, & NECO exams.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.greyColor, fontSize: 10)),
        ],
      ),
    );
  }
}

class _Msg {
  final bool isAi;
  final String text, time;
  const _Msg({required this.isAi, required this.text, required this.time});
}
