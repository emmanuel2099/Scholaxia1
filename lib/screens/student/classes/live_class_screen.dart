import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
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
  Timer? _wsReconnectTimer;
  Timer? _studentsPoll;
  Timer? _attendancePoll;
  bool _disposed = false;
  bool _classEnded = false;
  LiveKitClassService? _liveKit;
  LiveClassSaveRecorder? _saveRecorder;
  late final BoardController _board;

  bool _loading = true;
  bool _boardOpen = false;
  bool _screenShareOn = false;
  bool _saveActive = false;
  bool _saveHintShown = false;
  bool _handRaised = false;
  final Map<String, String> _raisedHands = {};
  String? _reactionBurst;
  Timer? _reactionClear;
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
  String? _teacherId;
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
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _board = BoardController(
      canDraw: widget.isTeacher,
      onSend: widget.isTeacher ? _sendBoardEvent : null,
    );
    _initSession();
  }

  @override
  void dispose() {
    _disposed = true;
    _tabController.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    _studentsPoll?.cancel();
    _reactionClear?.cancel();
    _attendancePoll?.cancel();
    _wsReconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _board.dispose();
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
      _teacherId = tokenData['teacher_id']?.toString() ??
          _classDetails?['teacher_id']?.toString();
      _micAllowed = widget.isTeacher || tokenData['mic_allowed'] != false;
      _cameraAllowed = widget.isTeacher || tokenData['camera_allowed'] != false;
      if (widget.isTeacher) {
        _micOn = true;
        _camOn = true;
      } else {
        // Open mic by default so teacher can hear the student immediately.
        _micAllowed = true;
        _micOn = true;
      }

      _classDetails = await _api.getLiveClassDetail(widget.classId);
      _participantCount = _classDetails?['active_attendees'] as int? ?? 0;
      _teacherId ??= _classDetails?['teacher_id']?.toString();
      final teacherField = _classDetails?['teacher'];
      if (_teacherId == null || _teacherId!.isEmpty) {
        if (teacherField is Map) {
          _teacherId = teacherField['id']?.toString();
        } else if (teacherField != null) {
          _teacherId = teacherField.toString();
        }
      }

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
    _wsSub?.cancel();
    _wsSub = channel.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _handleWsEvent(msg);
        } catch (_) {}
      },
      onError: (_) => _scheduleWsReconnect(),
      onDone: _scheduleWsReconnect,
      cancelOnError: true,
    );
    // Late joiners need the current board; teachers reply with history.
    try {
      channel.sink.add(jsonEncode({'event': 'request_board_sync'}));
    } catch (_) {}
  }

  void _scheduleWsReconnect() {
    if (_disposed || _classEnded) return;
    _channel = null;
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_disposed || _classEnded) return;
      try {
        await _connectWebSocket();
      } catch (_) {
        _scheduleWsReconnect();
      }
    });
  }

  void _handleWsEvent(Map<String, dynamic> msg) {
    final event = msg['event']?.toString() ?? '';
    switch (event) {
      case 'chat':
        // Server echoes chat back to the sender too; we already show our own
        // message locally, so skip the echo to avoid duplicates.
        final fromId = msg['user_id']?.toString() ?? '';
        if (fromId.isNotEmpty &&
            fromId.toLowerCase() == _userId.toLowerCase()) {
          break;
        }
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
          final uid = msg['user_id']?.toString() ?? '';
          final name = msg['name']?.toString() ?? 'Student';
          if (uid.isNotEmpty) {
            setState(() => _raisedHands[uid] = name);
          }
          _addChat('', '$name raised their hand.', system: true);
          _toast('$name raised their hand');
        }
        break;
      case 'lower_hand':
        if (widget.isTeacher) {
          final uid = msg['user_id']?.toString() ?? '';
          if (uid.isNotEmpty) {
            setState(() => _raisedHands.remove(uid));
          }
        }
        break;
      case 'reaction':
        final emoji = msg['emoji']?.toString() ?? '👍';
        final name = msg['name']?.toString() ?? 'Someone';
        _showReaction(emoji);
        _addChat('', '$name reacted $emoji', system: true);
        break;
      case 'mic_access_granted':
        if (!widget.isTeacher && _isMe(msg)) {
          setState(() => _micAllowed = true);
          _toast('Teacher allowed your mic — turning it on.');
          unawaited(_autoEnableMic());
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
        if (!widget.isTeacher && _isMe(msg)) {
          setState(() => _cameraAllowed = true);
          _toast('Teacher allowed your camera — turning it on.');
          unawaited(_autoEnableCamera());
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
        _board.handleRemoteMessage(msg);
        if (!widget.isTeacher) {
          final action = msg['action']?.toString() ?? '';
          if (action == 'board_open') {
            final open = msg['data'] is Map && msg['data']['open'] == true;
            if (mounted) setState(() => _boardOpen = open);
          } else if (action == 'draw' ||
              action == 'text' ||
              action == 'text_stream' ||
              action == 'erase' ||
              action == 'image') {
            // Auto-show board when teacher draws (matches website).
            if (!_boardOpen && mounted) setState(() => _boardOpen = true);
          }
        }
        break;
      case 'request_board_sync':
        if (widget.isTeacher) {
          _board.syncToRoom(boardOpen: _boardOpen);
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

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _toggleScreenShare() async {
    if (!widget.isTeacher || _liveKit == null) return;
    final next = !_screenShareOn;

    if (!next) {
      await _liveKit!.setScreenShareEnabled(false);
      if (mounted) setState(() => _screenShareOn = false);
      _toast('Screen sharing stopped');
      return;
    }

    try {
      // On desktop the user must pick which screen/window to share.
      String? sourceId;
      if (_isDesktop) {
        final source = await showDialog(
          context: context,
          builder: (_) => Theme(
            data: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xFF14121C),
              dialogBackgroundColor: const Color(0xFF14121C),
              colorScheme: ColorScheme.dark(
                surface: const Color(0xFF14121C),
                primary: context.accentColor,
              ),
            ),
            child: ScreenSelectDialog(),
          ),
        );
        if (source == null) return; // cancelled
        sourceId = (source as dynamic).id as String?;
        if (sourceId == null || sourceId.isEmpty) return;
      }

      // Board and screen share both use the top stage — close the board so the
      // shared screen is visible when sharing starts.
      if (_boardOpen) {
        setState(() => _boardOpen = false);
        _sendBoardEvent('board_open', {'open': false});
      }

      await _liveKit!.setScreenShareEnabled(true, sourceId: sourceId);
      if (_liveKit!.error != null) {
        _toast('Screen share was blocked. Allow screen capture and retry.');
        if (mounted) setState(() => _screenShareOn = false);
        return;
      }
      if (mounted) setState(() => _screenShareOn = true);
      _toast('Screen sharing started');
    } catch (_) {
      _toast('Screen share not available on this device');
      if (mounted) setState(() => _screenShareOn = false);
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

  Future<bool> _ensureMediaPermissions({
    bool camera = false,
    bool mic = false,
  }) async {
    if (kIsWeb) return true;
    try {
      if (camera) {
        final s = await Permission.camera.request();
        if (!s.isGranted) {
          _toast('Camera permission is needed. Enable it in settings.');
          return false;
        }
      }
      if (mic) {
        final s = await Permission.microphone.request();
        if (!s.isGranted) {
          _toast('Microphone permission is needed. Enable it in settings.');
          return false;
        }
      }
      return true;
    } catch (_) {
      _toast('Could not request mic/camera permission.');
      return false;
    }
  }

  Future<void> _connectLiveKit() async {
    if (!_hasValidLiveKitToken || _livekitUrl == null || _livekitToken == null) {
      return;
    }

    // Both teacher and student need mic permission to hear / be heard.
    final ok = await _ensureMediaPermissions(
      camera: widget.isTeacher,
      mic: true,
    );
    if (!ok && widget.isTeacher) {
      _toast('Enable microphone so students can hear you.');
    }

    _liveKit = LiveKitClassService(
      preferredTeacherIdentity: widget.isTeacher ? null : _teacherId,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );

    // Always publish mic for teacher; students when allowed.
    // Teacher also publishes camera so students can see them.
    final shouldPubMic = widget.isTeacher ? true : (_micAllowed && _micOn);
    final shouldPubCam = widget.isTeacher ? true : (_cameraAllowed && _camOn);
    if (widget.isTeacher) {
      _micOn = true;
      _camOn = true;
    }
    await _liveKit!.connect(
      url: _livekitUrl!,
      token: _livekitToken!,
      publishMic: shouldPubMic,
      publishCamera: shouldPubCam,
    );
    await _liveKit!.ensureRemoteAudioSubscribed();

    if (_liveKit!.error != null && mounted) {
      _toast('Video/audio could not connect. Chat still works.');
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
        // Match join: treat missing/null as allowed (open mic/cam by default).
        _micAllowed = tokenData['mic_allowed'] != false;
        _cameraAllowed = tokenData['camera_allowed'] != false;
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
      final presence = await _api.getLiveClassPresence(widget.classId);
      final students = presence['active_attendees'] as int? ??
          (presence['students'] is List
              ? (presence['students'] as List).length
              : 0);
      // Store student count only; UI adds the teacher once.
      if (mounted) setState(() => _participantCount = students);
    } catch (_) {
      try {
        final detail = await _api.getLiveClassDetail(widget.classId);
        final count = detail['active_attendees'] as int? ?? 0;
        if (mounted) setState(() => _participantCount = count);
      } catch (_) {}
    }
  }

  bool get _hasValidLiveKitToken {
    final t = _livekitToken ?? '';
    final u = _livekitUrl ?? '';
    return t.isNotEmpty &&
        u.isNotEmpty &&
        !t.contains('LIVEKIT_NOT_CONFIGURED') &&
        !t.contains('TOKEN_ERROR');
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
    if (text.isEmpty) return;
    if (_channel == null) {
      _toast('Reconnecting chat… try again in a moment.');
      _scheduleWsReconnect();
      return;
    }
    try {
      _channel!.sink.add(jsonEncode({'event': 'chat', 'text': text}));
      _addChat('You', text);
      _chatController.clear();
    } catch (_) {
      _toast('Message not sent — reconnecting.');
      _scheduleWsReconnect();
    }
  }

  void _toggleHand() {
    if (widget.isTeacher || _channel == null) return;
    const name = 'Student';
    if (_handRaised) {
      _channel!.sink.add(jsonEncode({'event': 'lower_hand'}));
    } else {
      _channel!.sink.add(jsonEncode({'event': 'raise_hand', 'name': name}));
    }
    setState(() => _handRaised = !_handRaised);
  }

  void _sendReaction(String emoji) {
    if (_channel == null) {
      _toast('Reconnecting chat… try again in a moment.');
      _scheduleWsReconnect();
      return;
    }
    final name = widget.isTeacher ? 'Teacher' : 'Student';
    try {
      _channel!.sink.add(jsonEncode({
        'event': 'reaction',
        'emoji': emoji,
        'name': name,
      }));
      _showReaction(emoji);
    } catch (_) {
      _toast('Reaction not sent — reconnecting.');
      _scheduleWsReconnect();
    }
  }

  void _showReaction(String emoji) {
    _reactionClear?.cancel();
    if (!mounted) return;
    setState(() => _reactionBurst = emoji);
    _reactionClear = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _reactionBurst = null);
    });
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
    if (next && !await _ensureMediaPermissions(mic: true)) return;
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

  Future<void> _autoEnableMic() async {
    if (widget.isTeacher || _micOn) return;
    if (_liveKit?.room == null) return;
    if (!await _ensureMediaPermissions(mic: true)) return;
    // The publish grant lives server-side; refresh the token so the reconnect
    // gets can_publish=true, then enable the mic. Retry once if it races.
    for (var attempt = 0; attempt < 2; attempt++) {
      await _refreshLiveKitToken(reconnect: true);
      try {
        await _liveKit!.setMicrophoneEnabled(true);
        if (mounted) setState(() => _micOn = true);
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  Future<void> _autoEnableCamera() async {
    if (widget.isTeacher || _camOn) return;
    if (_liveKit?.room == null) return;
    if (!await _ensureMediaPermissions(camera: true)) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      await _refreshLiveKitToken(reconnect: true);
      try {
        await _liveKit!.setCameraEnabled(true);
        if (mounted) setState(() => _camOn = true);
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
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
    if (next && !await _ensureMediaPermissions(camera: true)) return;
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

    // Mark ended and tell everyone the session is closing before we tear down.
    _classEnded = true;
    try {
      _channel?.sink.add(jsonEncode({
        'event': 'chat',
        'text': 'Class ended by the teacher.',
      }));
    } catch (_) {}

    String? errorMessage;
    try {
      await _api.endLiveClass(widget.classId);
    } on ApiException catch (e) {
      errorMessage = e.message;
    } catch (_) {}

    // Always tear down media and leave the screen, even if the API call failed
    // (e.g. the class was already ended server-side).
    _wsReconnectTimer?.cancel();
    try {
      await _liveKit?.disconnect();
    } catch (_) {}
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    if (!mounted) return;
    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    }
    Navigator.pop(context);
  }

  void _onClassEnded(String message) {
    if (!mounted) return;
    _classEnded = true;
    _wsReconnectTimer?.cancel();
    unawaited(_liveKit?.disconnect());
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
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            _videoArea(context),
            if (_reactionBurst != null) _reactionBanner(context),
            if (widget.isTeacher && _raisedHands.isNotEmpty)
              _raisedHandsStrip(context),
            _controls(context),
            _reactionRow(context),
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
            if (_tabController.index == 0) _inputBar(context),
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
    // Shrink the top stage while the keyboard is open (e.g. typing on the
    // board) so the rest of the layout still fits.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final stageHeight = keyboardOpen ? 130.0 : 220.0;

    // Board canvas lives at the top (video area) for everyone. The teacher's
    // toolbar + keyboard live at the bottom in the BOARD tab, both driven by
    // the same BoardController.
    if (_boardOpen) {
      return SizedBox(
        height: stageHeight,
        child: LiveClassBoardCanvas(controller: _board),
      );
    }

    if (remote != null) {
      return Container(
        height: stageHeight,
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
      height: stageHeight,
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

  Widget _reactionBanner(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 48,
        alignment: Alignment.center,
        child: Text(
          _reactionBurst ?? '',
          style: const TextStyle(fontSize: 34),
        ),
      ),
    );
  }

  Widget _raisedHandsStrip(BuildContext context) {
    final entries = _raisedHands.entries.toList();
    return Container(
      width: double.infinity,
      color: context.accentColor.withOpacity(0.12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Raised hands (${entries.length})',
            style: TextStyle(
              color: context.accentColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: entries.map((e) {
              return ActionChip(
                label: Text('✋ ${e.value}'),
                onPressed: () async {
                  await _allowMic(e.key);
                  if (mounted) {
                    setState(() => _raisedHands.remove(e.key));
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _reactionRow(BuildContext context) {
    const emojis = ['👍', '❤️', '😂', '👏', '🎉'];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      color: context.surfColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: emojis
            .map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => _sendReaction(e),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.accentColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            )
            .toList(),
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
            _btn(
              context,
              Icons.call_end,
              widget.isTeacher ? 'End' : 'Leave',
              widget.isTeacher ? _endClass : () => Navigator.maybePop(context),
              red: true,
            ),
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
      final total = _participantCount + 1; // students + teacher
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
                'Use reactions or raise hand below.',
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
              if (sid.isNotEmpty &&
                  _liveKit?.studentCameras[sid] != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: VideoTrackRenderer(
                      _liveKit!.studentCameras[sid]!,
                      key: ValueKey(
                        'student-cam-$sid-${_liveKit!.studentCameras[sid]!.hashCode}',
                      ),
                      fit: VideoViewFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
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
    return Column(
      children: [
        if (!_boardOpen)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.draw_rounded,
                        color: context.accentColor, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Tap "Board" above to open the whiteboard.\n'
                      'The board shows at the top; draw or type here.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: context.greyColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              child: LiveClassBoardControls(controller: _board),
            ),
          ),
      ],
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
