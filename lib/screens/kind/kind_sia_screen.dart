import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import 'kind_shared.dart';

class KindSiaScreen extends StatefulWidget {
  const KindSiaScreen({super.key});

  @override
  State<KindSiaScreen> createState() => _KindSiaScreenState();
}

class _KindSiaScreenState extends State<KindSiaScreen> {
  final _api = ApiService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  bool _loading = false;
  String _subject = 'General';
  List<String> _subjects = ['General'];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
    _messages.add(const _Msg(
      isAi: true,
      text:
          "Hi! I'm Sia — your friendly learning buddy. Ask me about homework, school, or anything you're curious about!",
    ));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final subs = await _api.kindSubjects();
      if (mounted && subs.isNotEmpty) setState(() => _subjects = subs);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _messages.add(_Msg(isAi: false, text: text));
      _loading = true;
    });
    _input.clear();
    try {
      final reply = await _api.kindSiaChat(question: text, subject: _subject);
      if (mounted) {
        setState(() => _messages.add(_Msg(isAi: true, text: reply)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _messages.add(_Msg(isAi: true, text: e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: KidColors.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.auto_awesome,
                        color: KidColors.accent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Text('Sia Kind',
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _subjects.contains(_subject)
                          ? _subject
                          : _subjects.first,
                      dropdownColor: context.cardColor,
                      style: TextStyle(color: context.textColor, fontSize: 13),
                      items: _subjects
                          .map((s) =>
                              DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _subject = v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _bubble(context, _messages[i]),
              ),
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: KidColors.accent, strokeWidth: 2),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: context.headerColor,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      style: TextStyle(color: context.textColor),
                      decoration: InputDecoration(
                        hintText: 'Ask Sia anything...',
                        hintStyle: TextStyle(color: context.greyLColor),
                        filled: true,
                        fillColor: context.surfColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _loading ? null : _send,
                    child: CircleAvatar(
                      backgroundColor: KidColors.accent,
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, _Msg m) {
    final isAi = m.isAi;
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isAi
              ? KidColors.accent.withOpacity(0.12)
              : context.surfColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isAi
                ? KidColors.accent.withOpacity(0.3)
                : context.borderColor,
          ),
        ),
        child: Text(m.text,
            style: TextStyle(
                color: context.textColor, fontSize: 14, height: 1.45)),
      ),
    );
  }
}

class _Msg {
  final bool isAi;
  final String text;
  const _Msg({required this.isAi, required this.text});
}
