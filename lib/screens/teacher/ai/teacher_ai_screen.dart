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
    _scrollToEnd();

    final greeting = _casualGreetingReply(text);
    if (greeting != null) {
      if (mounted) {
        setState(() {
          _messages.add(_AiMsg(role: 'assistant', text: greeting));
          _loading = false;
        });
      }
      _scrollToEnd();
      return;
    }

    try {
      final res = await _api.teacherAiAsk(
        task: 'general',
        subject: 'General',
        educationLevel: 'General',
        details: text,
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
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String? _casualGreetingReply(String text) {
    final t = text.trim().toLowerCase().replaceAll(RegExp(r'[!.?]+$'), '');
    const greetings = {
      'hi', 'hello', 'hey', 'hola', 'good morning', 'good afternoon',
      'good evening', 'gm', 'sup', 'yo',
    };
    if (greetings.contains(t)) {
      return "Hello! I'm your Scholaxia teaching assistant. "
          'What would you like help with — a lesson idea, assignment, quiz, or something else?';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Teacher AI',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Ask anything about teaching, classes, or your students.',
                      style: TextStyle(color: AppColors.grey, fontSize: 13)),
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
                          style: TextStyle(color: AppColors.grey, fontSize: 14),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bubble(_messages[i]),
                    ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                    color: AppColors.yellow, strokeWidth: 2),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: const BoxDecoration(
                color: AppColors.cardBg,
                border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(color: AppColors.white),
                      decoration: InputDecoration(
                        hintText: 'Ask Teacher AI...',
                        hintStyle: const TextStyle(color: AppColors.grey),
                        filled: true,
                        fillColor: AppColors.surfaceLight,
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
                            ? AppColors.yellow.withOpacity(0.5)
                            : AppColors.yellow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.black, size: 20),
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

  Widget _bubble(_AiMsg msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? AppColors.yellow.withOpacity(0.15) : AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUser
                ? AppColors.yellow.withOpacity(0.4)
                : const Color(0xFF2A2A2A),
          ),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isUser ? AppColors.white : AppColors.greyLight,
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
