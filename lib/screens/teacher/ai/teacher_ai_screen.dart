import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/chat_persistence_service.dart';
import '../../../services/sia_voice_input_service.dart';
import '../../../services/sia_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../teacher_shared.dart';

class TeacherAiScreen extends StatefulWidget {
  const TeacherAiScreen({super.key});

  @override
  State<TeacherAiScreen> createState() => _TeacherAiScreenState();
}

class _TeacherAiScreenState extends State<TeacherAiScreen> {
  static const _chatChannel = 'teacher_ai';

  final _api = ApiService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_AiMsg>[];
  bool _loading = false;
  bool _voiceOn = true;
  bool _listening = false;
  bool _isSpeaking = false;
  String _voiceCaption = '';
  int _unread = 0;
  String? _teacherName;
  final _voiceInput = SiaVoiceInputService.instance;

  @override
  void initState() {
    super.initState();
    SiaVoiceService.instance.onSpeakingChanged = (v) {
      if (mounted) setState(() => _isSpeaking = v);
    };
    SiaVoiceService.instance.init();
    _bootstrap();
  }

  Future<void> _speakAi(String text) async {
    if (!_voiceOn || text.trim().isEmpty) return;
    await SiaVoiceService.instance.speak(text);
  }

  Future<void> _toggleListen() async {
    if (_loading) return;

    if (_listening) {
      final text = await _voiceInput.stopAndCapture();
      setState(() {
        _listening = false;
        _voiceCaption = '';
      });
      if (text.isNotEmpty) await _sendText(text);
      return;
    }

    final ready = await _voiceInput.ensureReady(context);
    if (!ready || !mounted) return;

    setState(() {
      _listening = true;
      _voiceCaption = 'Speak now — tap Voice again when done';
      _inputCtrl.clear();
    });

    await _voiceInput.startListening(
      onPartial: (words) {
        if (!mounted) return;
        setState(() {
          _voiceCaption = words.isEmpty ? 'Speak now — tap Voice again when done' : words;
          _inputCtrl.text = words;
        });
      },
      onFinal: (words) async {
        if (!mounted || !_listening) return;
        setState(() {
          _listening = false;
          _voiceCaption = '';
        });
        await _voiceInput.stop();
        if (words.isNotEmpty) await _sendText(words);
      },
    );
  }

  Future<void> _bootstrap() async {
    final saved = await ChatPersistenceService.instance.load(_chatChannel);
    if (mounted && saved.isNotEmpty) {
      setState(() {
        _messages.addAll(saved.map((m) => _AiMsg(
              role: m.role ?? (m.isAi ? 'assistant' : 'user'),
              text: m.text,
            )));
      });
      _scrollToEnd();
    }
    await _loadProfile();
  }

  Future<void> _persistChat() async {
    if (_messages.isEmpty) return;
    await ChatPersistenceService.instance.save(
      _chatChannel,
      _messages
          .map((m) => StoredChatMessage(
                isAi: m.role != 'user',
                text: m.text,
                role: m.role,
              ))
          .toList(),
    );
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text('Delete your Teacher AI conversation on this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ChatPersistenceService.instance.clear(_chatChannel);
    setState(() => _messages.clear());
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    SiaVoiceService.instance.stop();
    SiaVoiceInputService.instance.stop();
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

  Future<void> _send() async => _sendText(_inputCtrl.text.trim());

  Future<void> _sendText(String text) async {
    if (text.isEmpty || _loading) return;
    setState(() {
      _messages.add(_AiMsg(role: 'user', text: text));
      _loading = true;
      _listening = false;
      _voiceCaption = '';
    });
    _inputCtrl.clear();

    final greeting = _casualGreetingReply(text);
    if (greeting != null) {
      if (mounted) {
        setState(() {
          _messages.add(_AiMsg(role: 'assistant', text: greeting));
          _loading = false;
        });
        await _persistChat();
        await _speakAi(greeting);
      }
      return;
    }

    await _persistChat();
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
        await _persistChat();
        await _speakAi(reply);
        _scrollToEnd();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _messages.add(_AiMsg(role: 'assistant', text: e.message)));
        await _persistChat();
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
    if (history.length > 14) {
      return history.sublist(history.length - 14);
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ask anything about teaching, classes, or your students.',
                          style: TextStyle(color: context.greyColor, fontSize: 13),
                        ),
                      ),
                      if (_messages.isNotEmpty)
                        TextButton.icon(
                          onPressed: _clearChat,
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 18, color: context.greyColor),
                          label: Text('Clear',
                              style: TextStyle(color: context.greyColor, fontSize: 12)),
                        ),
                      IconButton(
                        onPressed: () => setState(() => _voiceOn = !_voiceOn),
                        icon: Icon(
                          _voiceOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          color: context.accentColor,
                        ),
                        tooltip: _voiceOn ? 'Voice on' : 'Voice off',
                      ),
                    ],
                  ),
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
            if (_isSpeaking)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.volume_up_rounded, color: accent, size: 16),
                    const SizedBox(width: 6),
                    Text('Teacher AI is speaking...',
                        style: TextStyle(color: accent, fontSize: 12)),
                  ],
                ),
              ),
            if (_listening)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withOpacity(0.45)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mic_rounded, color: accent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _voiceCaption,
                        style: TextStyle(color: context.textColor, fontSize: 14, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: context.headerColor,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _toggleListen,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _listening ? accent.withOpacity(0.18) : accent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _listening ? accent : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                            color: _listening ? accent : (context.isDark ? Colors.black : Colors.white),
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _listening ? 'Send' : 'Voice',
                            style: TextStyle(
                              color: _listening ? accent : (context.isDark ? Colors.black : Colors.white),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
