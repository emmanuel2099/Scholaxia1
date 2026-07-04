import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/saved_live_class.dart';
import 'saved_live_class_service.dart';

/// Records a live class locally on the device (like desktop Save class).
class LiveClassSaveRecorder {
  LiveClassSaveRecorder();

  final _recorder = AudioRecorder();
  bool active = false;
  DateTime? startedAt;
  String? _tempPath;

  Future<bool> start() async {
    if (active) return true;

    final micOk = await Permission.microphone.request();
    if (!micOk.isGranted) return false;

    final dir = await getTemporaryDirectory();
    _tempPath =
        '${dir.path}/live_save_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _tempPath!,
    );

    startedAt = DateTime.now();
    active = true;
    return true;
  }

  Future<SavedLiveClass?> stopAndStore({
    required String title,
    required String subject,
    required String teacher,
    required String classId,
  }) async {
    if (!active) return null;

    final path = await _recorder.stop();
    active = false;

    final filePath = path ?? _tempPath;
    if (filePath == null || !File(filePath).existsSync()) return null;

    final duration = startedAt == null
        ? null
        : DateTime.now().difference(startedAt!).inSeconds;

    final saved = await SavedLiveClassService.instance.save(
      title: title,
      subject: subject,
      teacher: teacher,
      classId: classId,
      sourceFile: File(filePath),
      mediaType: 'audio',
      durationSeconds: duration,
    );

    startedAt = null;
    _tempPath = null;
    return saved;
  }

  Future<void> cancel() async {
    if (!active) return;
    await _recorder.stop();
    active = false;
    if (_tempPath != null) {
      final f = File(_tempPath!);
      if (await f.exists()) await f.delete();
    }
    startedAt = null;
    _tempPath = null;
  }

  void dispose() {
    _recorder.dispose();
  }
}
