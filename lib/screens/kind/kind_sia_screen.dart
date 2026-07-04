import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../api/api_service.dart';
import '../../services/chat_persistence_service.dart';
import '../../services/sia_voice_service.dart';
import '../../theme/app_theme.dart';

class KindSiaScreen extends StatefulWidget {
  const KindSiaScreen({super.key});

  @override
  State<KindSiaScreen> createState() => _KindSiaScreenState();
}

class _KindSiaScreenState extends State<KindSiaScreen> {
  static const _chatChannel = 'kind_sia';

  final _api = ApiService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  bool _loading = false;
  bool _voiceOn = true;
  bool _listening = false;
  String _subject = 'General';
  List<String> _subjects = ['General'];
  final _speech = SpeechToText();

  @override
  void initState() {
    super.initState();
    SiaVoiceService.instance.init();
    _bootstrap();
  }

  Future<void> _speakAi(String text) async {
    if (!_voiceOn || text.trim().isEmpty) return;
    await SiaVoiceService.instance.speak(text);
    if (mounted) setState(() {});
  }

  Future<void> _toggleListen() async {
    if (_loading) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize();
    if (!ok) return;
    if (mounted) setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        _input.text = r.recognizedWords;
        if (r.finalResult && mounted) {
          setState(() => _listening = false);
          _send();
        }
      },
    );
  }

  Future<void> _bootstrap() async {
    final saved = await ChatPersistenceService.instance.load(_chatChannel);
    if (!mounted) return;
    if (saved.isNotEmpty) {
      setState(() {
        _messages
          ..clear()
          ..addAll(saved.map((m) => _Msg(isAi: m.isAi, text: m.text)));
      });
      _scrollToBottom();
    } else {
      setState(() {
        _messages.add(_defaultWelcome());
      });
    }
    _loadSubjects();
  }

  _Msg _defaultWelcome() => const _Msg(
        isAi: true,
        text:
            "Hi! I'm Sia — your friendly learning buddy. Ask me about homework, school, or anything you're curious about!",
      );

  Future<void> _persistChat() async {
    await ChatPersistenceService.instance.save(
      _chatChannel,
      _messages
          .map((m) => StoredChatMessage(isAi: m.isAi, text: m.text))
          .toList(),
    );
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text('Delete your Sia chat on this device?'),
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
    setState(() {
      _messages
        ..clear()
        ..add(_defaultWelcome());
    });
    await _persistChat();
  }

  @override
  void dispose() {
    SiaVoiceService.instance.stop();
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
    _scrollToBottom();
    await _persistChat();
    try {
      final reply = await _api.kindSiaChat(
        question: text,
        subject: _subject,
        conversationHistory: _buildHistory(),
      );
      if (mounted) {
        setState(() => _messages.add(_Msg(isAi: true, text: reply)));
        _scrollToBottom();
        await _persistChat();
        await _speakAi(reply);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _messages.add(_Msg(isAi: true, text: e.message)));
        await _persistChat();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Map<String, dynamic>> _buildHistory() {
    final history = <Map<String, dynamic>>[];
    for (final m in _messages) {
      if (m.isAi && m.text.contains('friendly learning buddy')) continue;
      history.add({
        'role': m.isAi ? 'assistant' : 'user',
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
    return Scaffold(
      backgroundColor: context.bgColor,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppGradients.hero(context),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sia Kind',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Your AI learning buddy',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_messages.length > 1)
                      IconButton(
                        onPressed: _clearChat,
                        icon: Icon(Icons.delete_outline_rounded,
                            color: Colors.white.withOpacity(0.9)),
                        tooltip: 'Clear chat',
                      ),
                    IconButton(
                      onPressed: () => setState(() => _voiceOn = !_voiceOn),
                      icon: Icon(
                        _voiceOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        color: Colors.white.withOpacity(0.9),
                      ),
                      tooltip: _voiceOn ? 'Voice on' : 'Voice off',
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _subjects.contains(_subject)
                              ? _subject
                              : _subjects.first,
                          dropdownColor: context.cardColor,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          icon: Icon(Icons.expand_more,
                              color: Colors.white.withOpacity(0.9), size: 18),
                          items: _subjects
                              .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s,
                                      style: TextStyle(
                                          color: context.textColor))))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _subject = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _bubble(context, _messages[i]),
            ),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: context.accentColor,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Sia is thinking...',
                      style: TextStyle(
                          color: context.greyColor, fontSize: 12)),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.fromLTRB(
                12, 10, 12, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(
              color: context.headerColor,
              border: Border(top: BorderSide(color: context.borderColor)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggleListen,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _listening
                          ? context.accentColor.withOpacity(0.2)
                          : context.surfColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _listening ? context.accentColor : context.borderColor,
                      ),
                    ),
                    child: Icon(
                      _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _listening ? context.accentColor : context.greyColor,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
                          horizontal: 18, vertical: 12),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _loading ? null : _send,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primaryButton,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: context.accentColor.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, _Msg m) {
    final isAi = m.isAi;
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          gradient: isAi
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    context.accentColor.withOpacity(0.15),
                    context.accentColor.withOpacity(0.08),
                  ],
                )
              : null,
          color: isAi ? null : context.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isAi ? 4 : 18),
            bottomRight: Radius.circular(isAi ? 18 : 4),
          ),
          border: Border.all(
            color: isAi
                ? context.accentColor.withOpacity(0.25)
                : context.borderColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(context.isDark ? 0.15 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          m.text,
          style: TextStyle(
            color: context.textColor,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _Msg {
  final bool isAi;
  final String text;
  const _Msg({required this.isAi, required this.text});
}
