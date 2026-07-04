import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/chat_persistence_service.dart';
import '../../../services/sia_voice_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'sia_voice_classroom_screen.dart';

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
  String _studentName = 'Student';
  bool _loading = false;
  bool _voiceOn = true;
  List<_Msg> _messages = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    SiaVoiceService.instance.stop();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _speakAi(String text) async {
    if (!_voiceOn || text.trim().isEmpty) return;
    await SiaVoiceService.instance.speak(text);
  }

  void _openVoiceClassroom() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SiaVoiceClassroomScreen(
          studentName: _studentName,
          subjects: _subjects,
          initialSubject: _subject,
          onAsk: (question, subject) async {
            final r = await _api.siaAsk(
              question: question,
              subject: subject,
              educationLevel: _educationLevel,
              tutorMode: 'smart',
            );
            return SiaVoiceAskResult(board: r.board, speakText: r.sia);
          },
        ),
      ),
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
            "Hi! I'm Sia, your AI tutor. Type here for text chat, or tap the mic icon for voice chat with the board.",
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
    setState(() => _messages = [_defaultWelcome()]);
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
      final subjects = p.subjects.isNotEmpty ? p.subjects : _subjects;
      final level = p.educationLevel;
      final name = p.fullName.split(' ').first;
      setState(() {
        _studentName = p.fullName.isNotEmpty ? p.fullName : 'Student';
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
                ? "Hi $name! I'm Sia$levelText. Type a question or tap the mic for voice chat."
                : "Hi $name! I'm Sia$levelText. I know you study $subjText — type or use voice chat (mic icon).",
            time: _now(),
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;
    final now = _now();
    setState(() {
      _messages.add(_Msg(isAi: false, text: text, time: now));
      _inputCtrl.clear();
      _loading = true;
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
          Expanded(child: _buildMessages(context)),
          if (_loading) _buildThinking(context),
          _buildQuickChips(context),
          _buildInput(context),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final compactIcon = IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: AppGradients.hero(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(children: [
        const StudentBackButton(lightOnGradient: true),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sia AI Tutor',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2)),
              Text('Text chat — tap mic for voice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11,
                      height: 1.2)),
            ],
          ),
        ),
        IconButton(
          style: compactIcon,
          onPressed: _openVoiceClassroom,
          icon: Icon(Icons.mic_rounded, color: Colors.white.withOpacity(0.95), size: 22),
          tooltip: 'Voice chat',
        ),
        IconButton(
          style: compactIcon,
          onPressed: _messages.length <= 1 ? null : _clearChat,
          icon: Icon(Icons.delete_outline_rounded,
              color: Colors.white.withOpacity(0.9), size: 20),
          tooltip: 'Clear chat',
        ),
        IconButton(
          style: compactIcon,
          onPressed: () => setState(() => _voiceOn = !_voiceOn),
          icon: Icon(
            _voiceOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: Colors.white.withOpacity(0.9),
            size: 20,
          ),
          tooltip: _voiceOn ? 'Read replies aloud' : 'Mute read-aloud',
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
        Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: AppGradients.primaryButton,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
        const SizedBox(width: 8),
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Sia AI Tutor',
                style: TextStyle(
                    color: context.textColor, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Icon(Icons.bolt, color: context.accentColor, size: 12),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12)),
              border: Border.all(color: context.borderColor),
            ),
            child: Text(m.text,
                style: TextStyle(color: context.textColor, fontSize: 14, height: 1.5)),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Text(m.time, style: TextStyle(color: context.greyColor, fontSize: 10)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _speakAi(m.text),
              child: Icon(Icons.volume_up_rounded, size: 14, color: context.accentColor),
            ),
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
            ),
            child: Text(m.text,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
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
        Text('••• Sia is thinking...',
            style: TextStyle(color: context.greyColor, fontSize: 12)),
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
        _chip(context, '🎤 Voice chat', _openVoiceClassroom),
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
      child: Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
                color: context.surfColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.borderColor)),
            child: TextField(
              controller: _inputCtrl,
              style: TextStyle(color: context.textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type your question…',
                hintStyle: TextStyle(color: context.greyColor),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _loading ? null : _send,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _loading ? context.accentColor.withOpacity(0.5) : context.accentColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.send_rounded,
                color: context.isDark ? AppColors.background : Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }
}

class _Msg {
  final bool isAi;
  final String text, time;
  const _Msg({required this.isAi, required this.text, required this.time});
}
