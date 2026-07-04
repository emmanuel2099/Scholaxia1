import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../teacher_shared.dart';

class TeacherAiScreen extends StatefulWidget {
  const TeacherAiScreen({super.key});

  @override
  State<TeacherAiScreen> createState() => _TeacherAiScreenState();
}

class _TeacherAiScreenState extends State<TeacherAiScreen> {
  final _api = ApiService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_AiMsg>[];
  bool _loading = false;
  int _unread = 0;
  String? _teacherName;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _api.getTeacherMe();
      if (mounted) {
        setState(() => _teacherName = p['full_name']?.toString());
      }
    } catch (_) {}
    try {
      final n = await _api.unreadNotificationCount();
      if (mounted) {
        setState(() => _unread = n);
        teacherUnreadCount.value = n;
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _messages.add(_AiMsg(role: 'user', text: text));
      _loading = true;
    });
    _inputCtrl.clear();

    final greeting = _casualGreetingReply(text);
    if (greeting != null) {
      if (mounted) {
        setState(() {
          _messages.add(_AiMsg(role: 'assistant', text: greeting));
          _loading = false;
        });
      }
      return;
    }

    try {
      final res = await _api.teacherAiAsk(
        task: 'general',
        subject: 'General',
        educationLevel: 'SS2',
        details: text,
        conversationHistory: _buildHistory(),
      );
      final reply = res['result']?.toString() ?? 'No response.';
      if (mounted) {
        setState(() => _messages.add(_AiMsg(role: 'assistant', text: reply)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _messages.add(_AiMsg(role: 'assistant', text: e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _casualGreetingReply(String text) {
    final t = text.trim().toLowerCase().replaceAll(RegExp(r'[!.?]+$'), '');
    const greetings = {
      'hi', 'hello', 'hey', 'hola', 'good morning', 'good afternoon',
      'good evening', 'gm', 'sup', 'yo',
    };
    if (greetings.contains(t) && _messages.isEmpty) {
      return "Hello! I'm your Scholaxia teaching assistant. "
          'What would you like help with — a lesson plan, assignment, quiz, or something else?';
    }
    return null;
  }

  List<Map<String, dynamic>> _buildHistory() {
    final history = <Map<String, dynamic>>[];
    for (final m in _messages) {
      history.add({
        'role': m.role == 'user' ? 'user' : 'assistant',
        'content': m.text,
      });
    }
    if (history.length > 10) {
      return history.sublist(history.length - 10);
    }
    return history;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TeacherTopBar(
                api: _api,
                teacherName: _teacherName,
                unreadCount: _unread,
                onUnreadChanged: (n) => setState(() => _unread = n),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Teacher AI',
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Ask anything about teaching, classes, or your students.',
                      style: TextStyle(color: context.greyColor, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Type a question below to start chatting with Teacher AI.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.greyColor, fontSize: 14),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bubble(context, _messages[i]),
                    ),
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.all(8),
                child: CircularProgressIndicator(
                    color: accent, strokeWidth: 2),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: context.headerColor,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: TextStyle(color: context.textColor),
                      decoration: InputDecoration(
                        hintText: 'Ask Teacher AI...',
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
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _loading
                            ? accent.withOpacity(0.5)
                            : accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.send_rounded,
                          color: context.isDark ? Colors.black : Colors.white,
                          size: 20),
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

  Widget _bubble(BuildContext context, _AiMsg msg) {
    final isUser = msg.role == 'user';
    final accent = context.accentColor;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? accent.withOpacity(0.15) : context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUser
                ? accent.withOpacity(0.4)
                : context.borderColor,
          ),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isUser ? context.textColor : context.greyLColor,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _AiMsg {
  final String role;
  final String text;
  const _AiMsg({required this.role, required this.text});
}
