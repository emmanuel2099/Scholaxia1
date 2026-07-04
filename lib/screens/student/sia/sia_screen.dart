import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/chat_persistence_service.dart';
import '../../../models/sia_board_item.dart';
import '../../../services/sia_voice_input_service.dart';
import '../../../services/sia_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/sia_board_panel.dart';
import '../../../widgets/student_ui.dart';

class SiaScreen extends StatefulWidget {
  const SiaScreen({super.key});
  @override
  State<SiaScreen> createState() => _SiaScreenState();
}

class _SiaScreenState extends State<SiaScreen> {
  static const _chatChannel = 'student_sia';

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _api = ApiService();
  String _subject = 'Physics';
  List<String> _subjects = ['Physics', 'Mathematics', 'Biology', 'Chemistry', 'English'];
  String? _educationLevel;
  bool _loading = false;
  bool _voiceOn = true;
  bool _listening = false;
  bool _isSpeaking = false;
  String _voiceCaption = '';
  List<SiaBoardItem> _boardItems = [];
  bool _boardOpen = true;
  List<_Msg> _messages = [];
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

  @override
  void dispose() {
    SiaVoiceService.instance.stop();
    SiaVoiceInputService.instance.stop();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
      _voiceCaption = 'Speak now — tap mic again when done';
      _inputCtrl.clear();
    });

    await _voiceInput.startListening(
      onPartial: (words) {
        if (!mounted) return;
        setState(() {
          _voiceCaption = words.isEmpty ? 'Speak now — tap mic again when done' : words;
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
    if (!mounted) return;
    if (saved.isNotEmpty) {
      setState(() {
        _messages = saved
            .map((m) => _Msg(isAi: m.isAi, text: m.text, time: m.time ?? ''))
            .toList();
      });
      _scrollToEnd();
    } else {
      setState(() {
        _messages = [_defaultWelcome()];
      });
    }
    await _loadProfile();
  }

  _Msg _defaultWelcome() => _Msg(
        isAi: true,
        text:
            "Hi! I'm Sia, your AI tutor. Ask me anything — I'll teach what you want at your level.",
        time: _now(),
      );

  Future<void> _persistChat() async {
    await ChatPersistenceService.instance.save(
      _chatChannel,
      _messages
          .map((m) => StoredChatMessage(isAi: m.isAi, text: m.text, time: m.time))
          .toList(),
    );
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'This will delete your Sia conversation on this device. This cannot be undone.',
        ),
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
      _messages = [_defaultWelcome()];
      _boardItems = [];
    });
    await _persistChat();
    await _loadProfile();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _api.getStudentProfile();
      if (!mounted) return;
      final subjects = p.subjects.isNotEmpty
          ? p.subjects
          : _subjects;
      final level = p.educationLevel;
      final name = p.fullName.split(' ').first;
      setState(() {
        _subjects = subjects;
        if (!subjects.contains(_subject)) {
          _subject = subjects.first;
        }
        _educationLevel = (level != null && level.isNotEmpty) ? level : null;
        final onlyWelcome = _messages.length == 1 &&
            _messages.first.isAi &&
            (_messages.first.text.contains("I'm Sia") ||
                _messages.first.text.startsWith('Hi '));
        if (onlyWelcome) {
          final subjText = subjects.take(3).join(', ');
          final levelText = _educationLevel != null ? ' ($_educationLevel)' : '';
          _messages[0] = _Msg(
            isAi: true,
            text: subjText.isEmpty
                ? "Hi $name! I'm Sia$levelText. Ask me anything you want to learn today."
                : "Hi $name! I'm Sia$levelText. Tap the purple mic, speak your question — I'll answer with voice too. What should we work on?",
            time: _now(),
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _send() async => _sendText(_inputCtrl.text.trim());

  Future<void> _sendText(String text) async {
    if (text.isEmpty || _loading) return;
    final now = _now();
    setState(() {
      _messages.add(_Msg(isAi: false, text: text, time: now));
      _inputCtrl.clear();
      _loading = true;
      _listening = false;
      _voiceCaption = '';
    });
    await _persistChat();
    try {
      final history = _buildHistory();
      final r = await _api.siaAsk(
        question: text,
        subject: _subject,
        educationLevel: _educationLevel,
        conversationHistory: history,
        tutorMode: 'smart',
      );
      if (mounted) {
        setState(() {
          _messages.add(_Msg(isAi: true, text: r.sia, time: _now()));
          if (r.board.isNotEmpty) {
            _boardItems = r.board;
            _boardOpen = true;
          }
          _loading = false;
        });
        await _persistChat();
        _scrollToEnd();
        await _speakAi(r.sia);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_Msg(isAi: true, text: 'Sorry, I ran into an issue: ${e.message}', time: _now()));
          _loading = false;
        });
        await _persistChat();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add(_Msg(isAi: true, text: 'Something went wrong. Please try again.', time: _now()));
          _loading = false;
        });
        await _persistChat();
      }
    }
  }

  String _now() {
    final n = DateTime.now();
    final h = n.hour % 12 == 0 ? 12 : n.hour % 12;
    final m = n.minute.toString().padLeft(2, '0');
    final ampm = n.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  List<Map<String, dynamic>> _buildHistory() {
    final history = <Map<String, dynamic>>[];
    for (final m in _messages) {
      if (m.isAi && m.text.contains("I'm Sia") && _messages.indexOf(m) == 0) continue;
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
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          if (_boardOpen && _boardItems.isNotEmpty)
            SiaBoardPanel(
              items: _boardItems,
              onClose: () => setState(() => _boardOpen = false),
            ),
          if (!_boardOpen && _boardItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _boardOpen = true),
                  icon: Icon(Icons.menu_book_rounded, size: 16, color: context.accentColor),
                  label: Text('Show board (${_boardItems.length})',
                      style: TextStyle(color: context.accentColor, fontSize: 12)),
                ),
              ),
            ),
          Expanded(child: _buildMessages(context)),
          if (_loading) _buildThinking(context),
          if (_isSpeaking) _buildSpeaking(context),
          if (_listening) _buildListeningBanner(context),
          if (!_listening && !_loading) _buildQuickChips(context),
          _buildInput(context),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: AppGradients.hero(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(children: [
        const StudentBackButton(lightOnGradient: true),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sia AI Tutor',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              Text('Always here to help you learn',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 12)),
              if (_boardItems.isNotEmpty)
                Text('Board shows key points while Sia talks',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.65), fontSize: 10)),
            ],
          ),
        ),
        IconButton(
          onPressed: _messages.length <= 1 ? null : _clearChat,
          icon: Icon(Icons.delete_outline_rounded,
              color: Colors.white.withOpacity(0.9), size: 22),
          tooltip: 'Clear chat',
        ),
        IconButton(
          onPressed: () => setState(() => _voiceOn = !_voiceOn),
          icon: Icon(
            _voiceOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: Colors.white.withOpacity(0.9),
            size: 22,
          ),
          tooltip: _voiceOn ? 'Voice on' : 'Voice off',
        ),
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
          decoration: BoxDecoration(
            gradient: AppGradients.primaryButton,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
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
            GestureDetector(
              onTap: () => _speakAi(m.text),
              child: Icon(Icons.volume_up_rounded, size: 14, color: context.accentColor),
            ),
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
              gradient: AppGradients.primaryButton,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(m.text,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.5)),
          ),
          const SizedBox(height: 4),
          Text(m.time, style: TextStyle(color: context.greyColor, fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _buildListeningBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.accentColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.accentColor.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_rounded, color: context.accentColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _voiceCaption,
              style: TextStyle(color: context.textColor, fontSize: 14, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeaking(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(children: [
        const SizedBox(width: 38),
        Icon(Icons.graphic_eq_rounded, color: context.accentColor, size: 16),
        const SizedBox(width: 6),
        Text('Sia is speaking...', style: TextStyle(color: context.accentColor, fontSize: 12)),
      ]),
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
            GestureDetector(
              onTap: _toggleListen,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: _listening ? null : AppGradients.primaryButton,
                  color: _listening ? context.accentColor.withOpacity(0.18) : null,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _listening ? context.accentColor : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _listening ? context.accentColor : Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _listening ? 'Send' : 'Voice',
                      style: TextStyle(
                        color: _listening ? context.accentColor : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_messages.length > 1)
              GestureDetector(
                onTap: _clearChat,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.surfColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Icon(Icons.delete_outline_rounded, size: 16, color: context.greyColor),
                ),
              ),
            if (_messages.length > 1) const SizedBox(width: 8),
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
          Text(
            _listening
                ? 'Speak your question — tap Voice again to send'
                : 'Voice chat: tap Voice → speak → Sia answers with voice',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.greyColor, fontSize: 10),
          ),
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
