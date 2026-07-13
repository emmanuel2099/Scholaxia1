import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../api/api_service.dart';
import '../../../services/live_class_ring_service.dart';
import '../../../services/livekit_class_service.dart';
import '../../../theme/app_theme.dart';

/// WhatsApp-style group voice call (audio only).
class GroupVoiceCallScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final bool isCaller;
  final Map<String, dynamic>? initialToken;

  const GroupVoiceCallScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.isCaller = false,
    this.initialToken,
  });

  @override
  State<GroupVoiceCallScreen> createState() => _GroupVoiceCallScreenState();
}

class _GroupVoiceCallScreenState extends State<GroupVoiceCallScreen> {
  final _api = ApiService();
  LiveKitClassService? _lk;
  bool _connecting = true;
  bool _micOn = true;
  bool _ended = false;
  String _status = 'Connecting…';
  String? _error;
  Timer? _participantTimer;
  List<String> _names = [];

  @override
  void initState() {
    super.initState();
    LiveClassRingService.instance.stop();
    _start();
  }

  @override
  void dispose() {
    _participantTimer?.cancel();
    _lk?.disconnect();
    _lk?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() {
        _connecting = false;
        _error = 'Microphone permission is required for voice calls.';
      });
      return;
    }

    try {
      Map<String, dynamic> data;
      if (widget.initialToken != null) {
        data = widget.initialToken!;
      } else if (widget.isCaller) {
        data = await _api.startGroupVoiceCall(widget.groupId);
      } else {
        data = await _api.joinGroupVoiceCall(widget.groupId);
      }

      final url = data['livekit_url']?.toString() ?? '';
      final token = data['livekit_token']?.toString() ?? data['token']?.toString() ?? '';
      if (url.isEmpty ||
          token.isEmpty ||
          token.contains('LIVEKIT_NOT_CONFIGURED') ||
          token.startsWith('TOKEN_ERROR')) {
        setState(() {
          _connecting = false;
          _error =
              'Voice calling is not configured on the server yet (LiveKit).';
        });
        return;
      }

      _lk = LiveKitClassService(onChanged: () {
        if (!mounted) return;
        _refreshNames();
        setState(() {});
      });
      await _lk!.connect(url: url, token: token, publishMic: true);
      await _lk!.ensureRemoteAudioSubscribed();
      _refreshNames();
      _participantTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshNames(),
      );

      if (!mounted) return;
      setState(() {
        _connecting = false;
        _status = _lk!.connected ? 'Connected' : (_lk!.error ?? 'Failed');
        _error = _lk!.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e is ApiException ? e.message : 'Could not start call.';
      });
    }
  }

  void _refreshNames() {
    final room = _lk?.room;
    if (room == null) return;
    final names = <String>[];
    final local = room.localParticipant;
    if (local != null) {
      final n = local.name;
      names.add((n != null && n.isNotEmpty) ? n : 'You');
    }
    for (final p in room.remoteParticipants.values) {
      final n = p.name;
      names.add((n != null && n.isNotEmpty) ? n : 'Member');
    }
    if (mounted) setState(() => _names = names);
  }

  Future<void> _toggleMic() async {
    final next = !_micOn;
    await _lk?.setMicrophoneEnabled(next);
    if (mounted) setState(() => _micOn = next);
  }

  Future<void> _hangUp() async {
    if (_ended) return;
    _ended = true;
    try {
      await _api.endGroupVoiceCall(widget.groupId);
    } catch (_) {}
    await _lk?.disconnect();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF128C7E); // WhatsApp-ish green
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              widget.groupName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _connecting
                  ? 'Calling…'
                  : (_error ?? '$_status · Voice call'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 36),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _names.isEmpty
                    ? Center(
                        child: _AvatarCircle(
                          label: 'You',
                          accent: accent,
                          large: true,
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: _names.length,
                        itemBuilder: (_, i) => _AvatarCircle(
                          label: _names[i],
                          accent: accent,
                          speaking: i == 0 && _micOn,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundAction(
                    icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: _micOn ? 'Mute' : 'Unmute',
                    color: _micOn ? Colors.white24 : Colors.orange,
                    onTap: _connecting ? null : _toggleMic,
                  ),
                  _RoundAction(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    color: const Color(0xFFE53935),
                    large: true,
                    onTap: _hangUp,
                  ),
                  _RoundAction(
                    icon: Icons.volume_up_rounded,
                    label: 'Speaker',
                    color: Colors.white24,
                    onTap: () async {
                      await _lk?.ensureRemoteAudioSubscribed();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Incoming group call ringing sheet.
Future<void> showIncomingGroupCall(
  BuildContext context, {
  required String groupId,
  required String groupName,
  required String callerName,
}) async {
  LiveClassRingService.instance.resetStopFlag();
  LiveClassRingService.instance.startRingingNow();

  final action = await showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: const Color(0xFF1F2C34),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.call_rounded, color: Color(0xFF25D366), size: 40),
            const SizedBox(height: 12),
            Text(
              '$callerName is calling',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              groupName,
              style: TextStyle(color: Colors.white.withOpacity(0.65)),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, 'decline'),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, 'join'),
                    child: const Text('Join'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  LiveClassRingService.instance.stop();
  if (!context.mounted) return;
  if (action == 'join') {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupVoiceCallScreen(
          groupId: groupId,
          groupName: groupName,
          isCaller: false,
        ),
      ),
    );
  } else {
    try {
      await ApiService().declineGroupVoiceCall(groupId);
    } catch (_) {}
  }
}

class _AvatarCircle extends StatelessWidget {
  final String label;
  final Color accent;
  final bool large;
  final bool speaking;

  const _AvatarCircle({
    required this.label,
    required this.accent,
    this.large = false,
    this.speaking = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 120.0 : 88.0;
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withOpacity(0.25),
            border: Border.all(
              color: speaking ? const Color(0xFF25D366) : Colors.white24,
              width: speaking ? 3 : 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontSize: large ? 42 : 32,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool large;

  const _RoundAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 68.0 : 56.0;
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: Colors.white, size: large ? 32 : 26),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
