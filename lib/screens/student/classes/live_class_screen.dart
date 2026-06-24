import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../api/api_endpoints.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';

class LiveClassScreen extends StatefulWidget {
  final String subject;
  final String topic;
  final String classId;
  final String? roomId;
  final String? livekitToken;
  final String? livekitUrl;
  final String userId;
  final bool isTeacher;

  const LiveClassScreen({
    super.key,
    this.subject = 'Physics',
    this.topic = 'Kinematics',
    this.classId = '',
    this.roomId,
    this.livekitToken,
    this.livekitUrl,
    this.userId = '',
    this.isTeacher = false,
  });

  @override
  State<LiveClassScreen> createState() => _LiveClassScreenState();
}

class _LiveClassScreenState extends State<LiveClassScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  final _api = ApiService();

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  Timer? _studentsPoll;

  bool _loading = true;
  bool _handRaised = false;
  bool _micOn = true;
  bool _camOn = true;
  String? _error;
  String _userId = '';
  String? _roomId;
  String? _livekitToken;
  String? _livekitUrl;
  Map<String, dynamic>? _classDetails;
  List<_ChatMsg> _messages = [];
  List<Map<String, dynamic>> _students = [];

  static const _liveRed = Color(0xFFFF6B6B);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initSession();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    _studentsPoll?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    if (!widget.isTeacher && widget.classId.isNotEmpty) {
      _api.leaveLiveClass(widget.classId);
    }
    super.dispose();
  }

  Future<void> _initSession() async {
    if (widget.classId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    try {
      _userId = widget.userId.isNotEmpty
          ? widget.userId
          : (await _api.getUserId() ?? '');

      if (widget.isTeacher) {
        await _api.startLiveClass(widget.classId);
      } else {
        await _api.joinLiveClass(widget.classId);
      }

      final tokenData = await _api.getLiveClassToken(widget.classId);
      _roomId = widget.roomId ??
          tokenData['room_id']?.toString() ??
          tokenData['channel_id']?.toString();
      _livekitToken = widget.livekitToken ??
          tokenData['livekit_token']?.toString() ??
          tokenData['token']?.toString();
      _livekitUrl = widget.livekitUrl ?? tokenData['livekit_url']?.toString();

      _classDetails = await _api.getLiveClassDetail(widget.classId);

      String? wsWarning;
      try {
        await _connectWebSocket();
      } catch (_) {
        wsWarning = kIsWeb
            ? 'Live chat could not connect in the browser. Try the mobile app for full audio/video.'
            : 'Live chat could not connect. You can still use the class screen.';
      }

      if (widget.isTeacher) {
        _pollStudents();
        _studentsPoll = Timer.periodic(
          const Duration(seconds: 12),
          (_) => _pollStudents(),
        );
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _messages = [
            if (wsWarning != null)
              _ChatMsg(sender: '', text: wsWarning!, isSystem: true),
            _ChatMsg(
              sender: '',
              text: widget.isTeacher
                  ? 'You are live. Students can join and chat.'
                  : 'You joined the class. Chat is ready.',
              isSystem: true,
            ),
          ];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (e is ApiException) {
            _error = e.message;
          } else if (kIsWeb) {
            _error =
                'Could not join class in the browser. Try the Android/iOS app, or check your connection.';
          } else {
            _error = 'Could not join class.';
          }
        });
      }
    }
  }

  Future<void> _connectWebSocket() async {
    if (_roomId == null || _roomId!.isEmpty || _userId.isEmpty) return;

    final url = ApiEndpoints.liveClassWs(
      _roomId!,
      userId: _userId,
      role: widget.isTeacher ? 'teacher' : 'student',
    );

    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    _wsSub = channel.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _handleWsEvent(msg);
        } catch (_) {}
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _messages = [
              ..._messages,
              const _ChatMsg(
                sender: '',
                text: 'Chat disconnected. Re-open the class to reconnect.',
                isSystem: true,
              ),
            ];
          });
        }
      },
    );
  }

  void _handleWsEvent(Map<String, dynamic> msg) {
    final event = msg['event']?.toString() ?? '';
    switch (event) {
      case 'chat':
        final who = msg['role'] == 'teacher' ? 'Teacher' : 'Student';
        _addChat(who, msg['text']?.toString() ?? '');
        break;
      case 'user_joined':
        _addChat('', 'Someone joined the class.', system: true);
        if (widget.isTeacher) _pollStudents();
        break;
      case 'user_left':
        _addChat('', 'Someone left the class.', system: true);
        if (widget.isTeacher) _pollStudents();
        break;
      case 'class_ended':
        _onClassEnded(msg['message']?.toString() ?? 'Class ended.');
        break;
      case 'raise_hand':
        if (widget.isTeacher) {
          _addChat(
            '',
            '${msg['name'] ?? 'A student'} raised their hand.',
            system: true,
          );
        }
        break;
      case 'mic_access_granted':
        if (!widget.isTeacher && mounted) setState(() => _micOn = true);
        break;
      case 'mic_access_revoked':
        if (!widget.isTeacher) {
          if (mounted) setState(() => _micOn = false);
          _addChat('', msg['message']?.toString() ?? 'Mic turned off by teacher.',
              system: true);
        }
        break;
      default:
        break;
    }
  }

  void _addChat(String sender, String text, {bool system = false}) {
    if (!mounted) return;
    setState(() {
      _messages = [..._messages, _ChatMsg(sender: sender, text: text, isSystem: system)];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _hasValidLiveKitToken {
    final t = _livekitToken ?? '';
    final u = _livekitUrl ?? '';
    return t.isNotEmpty &&
        u.isNotEmpty &&
        !t.contains('LIVEKIT_NOT_CONFIGURED');
  }

  Future<void> _pollStudents() async {
    if (!widget.isTeacher || widget.classId.isEmpty) return;
    try {
      final raw = await _api.listLiveClassStudents(widget.classId);
      final list = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) setState(() => _students = list);
    } catch (_) {}
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty || _channel == null) return;
    _channel!.sink.add(jsonEncode({'event': 'chat', 'text': text}));
    _addChat('You', text);
    _chatController.clear();
  }

  void _toggleHand() {
    if (widget.isTeacher || _channel == null) return;
    if (_handRaised) {
      _channel!.sink.add(jsonEncode({'event': 'lower_hand'}));
    } else {
      _channel!.sink.add(jsonEncode({'event': 'raise_hand', 'name': 'Student'}));
    }
    setState(() => _handRaised = !_handRaised);
  }

  void _toggleMic() => setState(() => _micOn = !_micOn);
  void _toggleCam() => setState(() => _camOn = !_camOn);

  Future<void> _allowMic(String studentId) async {
    try {
      await _api.unmuteLiveClassStudent(widget.classId, studentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mic allowed for student.')),
        );
      }
      _pollStudents();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _revokeMic(String studentId) async {
    try {
      await _api.muteLiveClassStudent(widget.classId, studentId);
      _pollStudents();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _endClass() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('End class?', style: TextStyle(color: AppColors.white)),
        content: const Text(
          'This will end the session for all students.',
          style: TextStyle(color: AppColors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Class', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _api.endLiveClass(widget.classId);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onClassEnded(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Class ended', style: TextStyle(color: AppColors.white)),
        content: Text(message, style: const TextStyle(color: AppColors.grey)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String get _title => _classDetails?['title'] as String? ?? widget.topic;
  String get _subject => _classDetails?['subject'] as String? ?? widget.subject;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.bgColor,
        body: Center(
          child: CircularProgressIndicator(color: context.accentColor),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: context.bgColor,
        appBar: AppBar(
          backgroundColor: context.headerColor,
          foregroundColor: context.textColor,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.textColor)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            _videoArea(context),
            _controls(context),
            _tabBar(context),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_chat(context), _participants(context)],
              ),
            ),
            _inputBar(context),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.headerColor,
          border: Border(bottom: BorderSide(color: context.borderColor)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.maybePop(context),
              child: Icon(Icons.arrow_back, color: context.textColor, size: 22),
            ),
            const SizedBox(width: 12),
            Icon(Icons.auto_awesome, color: context.accentColor, size: 16),
            const SizedBox(width: 4),
            Text('Scholaxia',
                style: TextStyle(
                    color: context.accentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title,
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(_subject,
                      style: TextStyle(color: context.greyColor, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (_classDetails?['is_live'] == true || widget.isTeacher)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _liveRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _liveRed.withOpacity(0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 3, backgroundColor: _liveRed),
                    SizedBox(width: 4),
                    Text('LIVE',
                        style: TextStyle(
                            color: _liveRed,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            if (widget.isTeacher) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _endClass,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                tooltip: 'End class',
              ),
            ],
          ],
        ),
      );

  Widget _videoArea(BuildContext context) {
    final videoBg = context.isDark ? Colors.black : const Color(0xFF1F2937);

    return Container(
      height: 220,
      color: videoBg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _camOn ? Icons.videocam_outlined : Icons.videocam_off_outlined,
              color: context.accentColor.withOpacity(0.7),
              size: 48,
            ),
            const SizedBox(height: 10),
            Text(
              _hasValidLiveKitToken
                  ? 'Live video uses LiveKit on desktop.\nMobile: chat + mic controls active.'
                  : 'Chat-only mode (LiveKit not configured on server)',
              style: TextStyle(
                  color: context.isDark
                      ? context.greyColor
                      : Colors.white.withOpacity(0.85),
                  fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _subject.toUpperCase(),
              style: TextStyle(
                color: context.accentColor,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: context.surfColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _btn(context, _micOn ? Icons.mic : Icons.mic_off, 'Mic', _toggleMic),
            _btn(context, _camOn ? Icons.videocam : Icons.videocam_off, 'Cam',
                _toggleCam),
            if (!widget.isTeacher)
              _btn(context, Icons.pan_tool_alt_outlined, 'Hand', _toggleHand),
            _btn(context, Icons.call_end, 'Leave',
                () => Navigator.maybePop(context),
                red: true),
          ],
        ),
      );

  Widget _btn(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool red = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: red
                    ? _liveRed
                    : (context.isDark
                        ? AppColors.surfaceLight
                        : context.accentColor.withOpacity(0.12)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: red
                    ? Colors.white
                    : (context.isDark ? Colors.white : context.accentColor),
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(color: context.greyColor, fontSize: 10)),
          ],
        ),
      );

  Widget _tabBar(BuildContext context) => Container(
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.borderColor))),
        child: TabBar(
          controller: _tabController,
          labelColor: context.accentColor,
          unselectedLabelColor: context.greyColor,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          indicatorColor: context.accentColor,
          indicatorWeight: 2,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: 'CHAT (${_messages.length})'),
            Tab(text: 'STUDENTS (${_students.length})'),
          ],
        ),
      );

  Widget _chat(BuildContext context) {
    if (_messages.isEmpty) {
      return Center(
        child: Text('No messages yet.',
            style: TextStyle(color: context.greyColor)),
      );
    }
    return ListView.builder(
      controller: _chatScroll,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        if (m.isSystem) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: Text(m.text,
                  style: TextStyle(color: context.greyColor, fontSize: 12)),
            ),
          );
        }
        final isMe = m.sender == 'You';
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: isMe
                  ? context.accentColor.withOpacity(0.12)
                  : context.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isMe
                    ? context.accentColor.withOpacity(0.3)
                    : context.borderColor,
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (m.sender.isNotEmpty)
                  Text(m.sender,
                      style: TextStyle(
                          color: context.accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                Text(m.text,
                    style: TextStyle(color: context.textColor, fontSize: 14)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _participants(BuildContext context) {
    if (!widget.isTeacher) {
      return Center(
        child: Text('${_students.length} participant(s) in class.',
            style: TextStyle(color: context.greyColor)),
      );
    }
    if (_students.isEmpty) {
      return Center(
        child: Text('Waiting for students to join…',
            style: TextStyle(color: context.greyColor)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = _students[i];
        final name = s['name']?.toString() ?? 'Student';
        final sid = s['student_id']?.toString() ?? '';
        final micAllowed = s['mic_allowed'] == true;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: context.accentColor.withOpacity(0.15),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'S',
                    style: TextStyle(
                        color: context.accentColor,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: TextStyle(
                        color: context.textColor, fontWeight: FontWeight.w600)),
              ),
              if (micAllowed)
                TextButton(
                  onPressed: sid.isEmpty ? null : () => _revokeMic(sid),
                  child: const Text('Revoke mic',
                      style: TextStyle(color: Colors.red, fontSize: 11)),
                )
              else
                TextButton(
                  onPressed: sid.isEmpty ? null : () => _allowMic(sid),
                  child: Text('Allow mic',
                      style: TextStyle(
                          color: context.accentColor, fontSize: 11)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _inputBar(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: context.bgColor,
          border: Border(top: BorderSide(color: context.borderColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: context.surfColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.borderColor),
                ),
                child: TextField(
                  controller: _chatController,
                  style: TextStyle(color: context.textColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Send a message…',
                    hintStyle: TextStyle(color: context.greyColor),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _sendChat(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendChat,
              child: Icon(Icons.send_rounded,
                  color: context.accentColor, size: 22),
            ),
          ],
        ),
      );
}

class _ChatMsg {
  final String sender;
  final String text;
  final bool isSystem;
  const _ChatMsg({
    required this.sender,
    required this.text,
    this.isSystem = false,
  });
}
