import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../theme/app_theme.dart';

/// Record a voice note for community posts / announcements.
class VoiceNoteRecorder extends StatefulWidget {
  final void Function(List<int> bytes, String filename) onRecorded;
  final VoidCallback? onCleared;

  const VoiceNoteRecorder({
    super.key,
    required this.onRecorded,
    this.onCleared,
  });

  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  int _seconds = 0;
  List<int>? _bytes;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<bool> _ensureMic() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (path != null) {
        final data = await File(path).readAsBytes();
        setState(() {
          _recording = false;
          _bytes = data;
        });
        widget.onRecorded(data, 'voice_note.m4a');
      } else {
        setState(() => _recording = false);
      }
      return;
    }

    if (!await _ensureMic()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );
    setState(() {
      _recording = true;
      _seconds = 0;
      _bytes = null;
    });
    _tick();
  }

  void _tick() async {
    while (_recording && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (_recording && mounted) setState(() => _seconds++);
    }
  }

  void _clear() {
    setState(() {
      _bytes = null;
      _seconds = 0;
    });
    widget.onCleared?.call();
  }

  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleRecord,
                icon: Icon(
                  _recording ? Icons.stop_rounded : Icons.mic_none_rounded,
                  color: _recording ? Colors.red : accent,
                ),
                label: Text(
                  _recording
                      ? 'Stop (${_formatTime(_seconds)})'
                      : (_bytes != null ? 'Record again' : 'Record voice note'),
                  style: TextStyle(color: context.textColor),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: _recording ? Colors.red : context.borderColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (_bytes != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _clear,
                icon: Icon(Icons.delete_outline, color: context.greyColor),
              ),
            ],
          ],
        ),
        if (_recording)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Recording… tap stop when done',
                style: TextStyle(color: Colors.red, fontSize: 12)),
          ),
        if (_bytes != null && !_recording)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: accent, size: 18),
                const SizedBox(width: 6),
                Text('Voice note ready — tap Post / Send',
                    style: TextStyle(color: context.greyColor, fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }
}
