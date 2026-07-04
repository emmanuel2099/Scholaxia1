import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../api/api_endpoints.dart';
import '../../../api/api_service.dart';
import '../../../services/livekit_class_service.dart';
import '../../../services/live_class_save_recorder.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/live_class_whiteboard.dart';

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
  Timer? _attendancePoll;
  LiveKitClassService? _liveKit;
  LiveClassSaveRecorder? _saveRecorder;
  final _boardKey = GlobalKey<LiveClassWhiteboardState>();

  bool _loading = true;
  bool _boardOpen = false;
  bool _screenShareOn = false;
  bool _saveActive = false;
  bool _saveHintShown = false;
  bool _handRaised = false;
  bool _micOn = false;
  bool _camOn = false;
  bool _micAllowed = false;
  bool _cameraAllowed = false;
  int _participantCount = 0;
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
    _tabController = TabController(
      length: widget.isTeacher ? 3 : 2,
      vsync: this,
    );
    _initSession();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    _studentsPoll?.cancel();
    _attendancePoll?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _liveKit?.disconnect();
    _liveKit?.dispose();
    if (_saveActive) {
      unawaited(_stopSaveClass(showNotice: false));
    }
    _saveRecorder?.dispose();
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
      _micAllowed = widget.isTeacher || tokenData['mic_allowed'] == true;
      _cameraAllowed = widget.isTeacher || tokenData['camera_allowed'] == true;
      if (widget.isTeacher) {
        _micOn = true;
        _camOn = true;
      }

      _classDetails = await _api.getLiveClassDetail(widget.classId);
      _participantCount = _classDetails?['active_attendees'] as int? ?? 0;

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
      } else {
        _attendancePoll = Timer.periodic(
          const Duration(seconds: 12),
          (_) => _pollAttendanceCount(),
        );
      }

      if (_hasValidLiveKitToken) {
        await _connectLiveKit();
      }

      if (!widget.isTeacher && !_saveHintShown) {
        _saveHintShown = true;
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _messages = [
            if (wsWarning != null)
              _ChatMsg(sender: '', text: wsWarning, isSystem: true),
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
        if (widget.isTeacher) {
          _pollStudents();
        } else {
          _pollAttendanceCount();
        }
        break;
      case 'user_left':
        if (widget.isTeacher) {
          _pollStudents();
        } else {
          _pollAttendanceCount();
        }
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
        if (!widget.isTeacher && _isMe(msg) && !_micAllowed) {
          setState(() => _micAllowed = true);
          _toast('Mic allowed — tap Mic to speak.');
        }
        break;
      case 'mic_access_update':
        if (!widget.isTeacher && _isMe(msg)) {
          final allowed = msg['has_mic'] == true;
          setState(() => _micAllowed = allowed);
          if (!allowed) {
            _micOn = false;
            unawaited(_liveKit?.setMicrophoneEnabled(false));
          }
        }
        break;
      case 'mic_access_revoked':
        if (!widget.isTeacher && _isMe(msg)) {
          if (mounted) setState(() {
            _micAllowed = false;
            _micOn = false;
          });
          unawaited(_liveKit?.setMicrophoneEnabled(false));
        }
        break;
      case 'camera_access_granted':
        if (!widget.isTeacher && _isMe(msg) && !_cameraAllowed) {
          setState(() => _cameraAllowed = true);
          _toast('Camera allowed — tap Cam.');
        }
        break;
      case 'camera_access_update':
        if (!widget.isTeacher && _isMe(msg)) {
          final allowed = msg['has_camera'] == true;
          setState(() => _cameraAllowed = allowed);
          if (!allowed) {
            _camOn = false;
            unawaited(_liveKit?.setCameraEnabled(false));
          }
        }
        break;
      case 'camera_access_revoked':
        if (!widget.isTeacher && _isMe(msg)) {
          if (mounted) setState(() {
            _cameraAllowed = false;
            _camOn = false;
          });
          unawaited(_liveKit?.setCameraEnabled(false));
        }
        break;
      case 'whiteboard':
        _boardKey.currentState?.handleRemoteMessage(msg);
        if (!widget.isTeacher && msg['action'] == 'board_open') {
          final open = msg['data'] is Map && msg['data']['open'] == true;
          if (mounted) setState(() => _boardOpen = open);
        }
        break;
      default:
        break;
    }
  }

  void _sendBoardEvent(String action, Map<String, dynamic> data) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'event': 'whiteboard',
      'action': action,
      'data': data,
    }));
  }

  Future<void> _toggleBoard() async {
    if (!widget.isTeacher) return;
    final next = !_boardOpen;
    setState(() => _boardOpen = next);
    _sendBoardEvent('board_open', {'open': next});
    if (next) _tabController.animateTo(2);
  }

  Future<void> _toggleScreenShare() async {
    if (!widget.isTeacher || _liveKit == null) return;
    final next = !_screenShareOn;
    try {
      await _liveKit!.setScreenShareEnabled(next);
      if (mounted) setState(() => _screenShareOn = next);
      if (next) {
        _toast('Screen sharing started');
      }
    } catch (_) {
      _toast('Screen share not available on this device');
    }
  }

  Future<void> _allowCamera(String studentId) async {
    try {
      await _api.allowLiveClassCamera(widget.classId, studentId);
      _pollStudents();
      if (mounted) _toast('Camera allowed for student.');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _revokeCamera(String studentId) async {
    try {
      await _api.revokeLiveClassCamera(widget.classId, studentId);
      _pollStudents();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isMe(Map<String, dynamic> msg) {
    final target = msg['target_user_id']?.toString() ?? msg['user_id']?.toString();
    if (target == null || target.isEmpty) return true;
    return target.toLowerCase() == _userId.toLowerCase();
  }

  Future<void> _connectLiveKit() async {
    if (!_hasValidLiveKitToken || _livekitUrl == null || _livekitToken == null) {
      return;
    }

    _liveKit = LiveKitClassService(onChanged: () {
      if (mounted) setState(() {});
    });

    await _liveKit!.connect(
      url: _livekitUrl!,
      token: _livekitToken!,
      publishMic: widget.isTeacher && _micOn,
      publishCamera: widget.isTeacher && _camOn,
    );

    if (_liveKit!.error != null && mounted) {
      _toast('Video could not connect. Chat still works.');
    }
  }

  Future<bool> _refreshLiveKitToken({bool reconnect = false}) async {
    try {
      final tokenData = await _api.getLiveClassToken(widget.classId);
      final newToken = tokenData['livekit_token']?.toString() ??
          tokenData['token']?.toString();
      final newUrl = tokenData['livekit_url']?.toString() ?? _livekitUrl;
      if (newToken == null || newToken.isEmpty || newUrl == null) return false;

      _livekitToken = newToken;
      _livekitUrl = newUrl;
      if (!widget.isTeacher) {
        _micAllowed = tokenData['mic_allowed'] == true;
        _cameraAllowed = tokenData['camera_allowed'] == true;
      }

      if (reconnect && _liveKit != null) {
        await _liveKit!.reconnect(
          url: _livekitUrl!,
          token: _livekitToken!,
          micOn: _micOn,
          camOn: _camOn,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pollAttendanceCount() async {
    if (widget.classId.isEmpty) return;
    try {
      final detail = await _api.getLiveClassDetail(widget.classId);
      final count = detail['active_attendees'] as int? ?? 0;
      if (mounted) setState(() => _participantCount = count);
    } catch (_) {}
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

  Future<void> _toggleMic() async {
    if (!widget.isTeacher && !_micAllowed) {
      _toast('Wait for teacher to allow your mic.');
      return;
    }
    if (_liveKit?.room == null) {
      _toast('Video still connecting…');
      return;
    }

    final next = !_micOn;
    if (next && !widget.isTeacher) {
      await _refreshLiveKitToken(reconnect: true);
    }
    try {
      await _liveKit!.setMicrophoneEnabled(next);
      if (mounted) setState(() => _micOn = next);
    } catch (e) {
      _toast('Mic error');
    }
  }

  Future<void> _toggleCam() async {
    if (!widget.isTeacher && !_cameraAllowed) {
      _toast('Wait for teacher to allow your camera.');
      return;
    }
    if (_liveKit?.room == null) {
      _toast('Video still connecting…');
      return;
    }

    final next = !_camOn;
    if (next && !widget.isTeacher) {
      await _refreshLiveKitToken(reconnect: true);
    }
    try {
      await _liveKit!.setCameraEnabled(next);
      if (mounted) setState(() => _camOn = next);
    } catch (e) {
      _toast('Camera error');
    }
  }
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

  Future<void> _toggleSaveClass() async {
    if (widget.isTeacher) return;
    if (_saveActive) {
      await _stopSaveClass(showNotice: true);
      return;
    }

    _saveRecorder ??= LiveClassSaveRecorder();
    final ok = await _saveRecorder!.start();
    if (!ok) {
      _toast('Microphone needed to save class.');
      return;
    }

    if (mounted) setState(() => _saveActive = true);
    _toast('Recording… tap Stop when done.');
  }

  Future<void> _stopSaveClass({required bool showNotice}) async {
    if (!_saveActive || _saveRecorder == null) return;

    final teacherName =
        _classDetails?['teacher_name']?.toString() ?? 'Teacher';

    final saved = await _saveRecorder!.stopAndStore(
      title: _title,
      subject: _subject,
      teacher: teacherName,
      classId: widget.classId,
    );

    if (mounted) setState(() => _saveActive = false);

    if (showNotice && saved != null) {
      _toast('Saved — open Saved tab to watch.');
    }
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
                children: [
                  _chat(context),
                  _participants(context),
                  if (widget.isTeacher) _boardTab(context),
                ],
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
            if (!widget.isTeacher) ...[
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: _toggleSaveClass,
                icon: Icon(
                  _saveActive ? Icons.stop_rounded : Icons.save_alt_rounded,
                  size: 16,
                ),
                label: Text(
                  _saveActive ? 'Stop' : 'Save',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: _saveActive ? Colors.red : context.accentColor,
                  backgroundColor: _saveActive
                      ? Colors.red.withOpacity(0.12)
                      : context.accentColor.withOpacity(0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
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
    final remote = _liveKit?.primaryRemoteVideo;
    final lkConnected = _liveKit?.connected == true;

    if (_boardOpen) {
      return SizedBox(
        height: 220,
        child: LiveClassWhiteboard(
          key: _boardKey,
          canDraw: widget.isTeacher,
          onSend: widget.isTeacher ? _sendBoardEvent : null,
        ),
      );
    }

    if (remote != null) {
      return Container(
        height: 220,
        color: videoBg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoTrackRenderer(
              remote,
              key: ValueKey(remote.mediaStreamTrack.id ?? remote.hashCode),
              fit: VideoViewFit.contain,
            ),
            if (_liveKit?.showingScreenShare == true)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'SCREEN / BOARD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      height: 220,
      color: videoBg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              lkConnected ? Icons.videocam_off_outlined : Icons.videocam_outlined,
              color: context.accentColor.withOpacity(0.7),
              size: 48,
            ),
            const SizedBox(height: 10),
            Text(
              !_hasValidLiveKitToken
                  ? 'Chat only — video not configured'
                  : (_liveKit?.placeholderMessage ?? 'Connecting…'),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: context.surfColor,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _btn(
              context,
              _micOn ? Icons.mic : Icons.mic_off,
              'Mic',
              _toggleMic,
              enabled: widget.isTeacher || _micAllowed,
            ),
            _btn(
              context,
              _camOn ? Icons.videocam : Icons.videocam_off,
              'Cam',
              _toggleCam,
              enabled: widget.isTeacher || _cameraAllowed,
            ),
            if (widget.isTeacher) ...[
              _btn(
                context,
                _boardOpen ? Icons.close_fullscreen : Icons.draw_rounded,
                'Board',
                _toggleBoard,
              ),
              _btn(
                context,
                _screenShareOn ? Icons.stop_screen_share : Icons.screen_share,
                'Share',
                _toggleScreenShare,
              ),
            ],
            if (!widget.isTeacher)
              _btn(
                context,
                _saveActive ? Icons.stop_rounded : Icons.save_alt_rounded,
                _saveActive ? 'Stop' : 'Save',
                _toggleSaveClass,
                red: _saveActive,
              ),
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
    bool enabled = true,
  }) =>
      GestureDetector(
        onTap: enabled ? onTap : onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
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
            Tab(
              text: widget.isTeacher
                  ? 'STUDENTS (${_students.length})'
                  : 'IN CLASS (${_participantCount + 1})',
            ),
            if (widget.isTeacher) const Tab(text: 'BOARD'),
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
      final total = _participantCount + 1;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, color: context.accentColor, size: 40),
              const SizedBox(height: 12),
              Text(
                '$total in class',
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You and your teacher are connected.\n'
                'Mic and camera need teacher approval.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.greyColor, fontSize: 13),
              ),
            ],
          ),
        ),
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
        final camAllowed = s['camera_allowed'] == true;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                            color: context.textColor,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (micAllowed)
                    OutlinedButton(
                      onPressed: sid.isEmpty ? null : () => _revokeMic(sid),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Revoke mic', style: TextStyle(fontSize: 11)),
                    )
                  else
                    FilledButton(
                      onPressed: sid.isEmpty ? null : () => _allowMic(sid),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.accentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Allow mic', style: TextStyle(fontSize: 11)),
                    ),
                  if (camAllowed)
                    OutlinedButton(
                      onPressed: sid.isEmpty ? null : () => _revokeCamera(sid),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Revoke cam', style: TextStyle(fontSize: 11)),
                    )
                  else
                    OutlinedButton(
                      onPressed: sid.isEmpty ? null : () => _allowCamera(sid),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.accentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Allow cam', style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _boardTab(BuildContext context) {
    return LiveClassWhiteboard(
      key: _boardKey,
      canDraw: widget.isTeacher,
      onSend: widget.isTeacher ? _sendBoardEvent : null,
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
