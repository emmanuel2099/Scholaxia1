import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../theme/app_theme.dart';

/// Inline audio player for community voice notes.
class VoiceNotePlayer extends StatefulWidget {
  final String mediaUrl;
  final String? label;

  const VoiceNotePlayer({
    super.key,
    required this.mediaUrl,
    this.label,
  });

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final raw = widget.mediaUrl;
      if (raw.startsWith('/') || RegExp(r'^[A-Za-z]:\\').hasMatch(raw)) {
        await _player.play(DeviceFileSource(raw));
      } else {
        await _player.play(UrlSource(ApiService().resolveMediaUrl(raw)));
      }
      if (mounted) setState(() {
        _playing = true;
        _loading = false;
      });
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _loading ? null : _toggle,
            icon: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: context.accentColor),
                  )
                : Icon(
                    _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    color: context.accentColor,
                    size: 36,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label ?? 'Voice note',
                  style: TextStyle(
                      color: context.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                Text('Tap to listen',
                    style: TextStyle(color: context.greyColor, fontSize: 11)),
              ],
            ),
          ),
          Icon(Icons.mic, color: context.accentColor, size: 18),
        ],
      ),
    );
  }
}
