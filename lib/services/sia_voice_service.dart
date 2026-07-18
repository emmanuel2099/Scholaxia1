import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_service.dart';

/// Speaks Sia / Teacher AI / Kind replies / kids games.
/// Prefers cloud MP3 (ElevenLabs → Edge TTS → gTTS on server).
/// Falls back to on-device TTS on mobile/macOS only — flutter_tts can
/// native-crash the Windows/Linux process.
class SiaVoiceService {
  SiaVoiceService._();
  static final instance = SiaVoiceService._();

  /// Device flutter_tts is unsafe on Windows/Linux (native crash).
  static bool get _deviceTtsSupported =>
      !kIsWeb && !Platform.isWindows && !Platform.isLinux;

  final _player = AudioPlayer();
  FlutterTts? _tts;
  bool _ready = false;
  bool _speaking = false;
  bool _deviceTtsOk = false;
  void Function(bool speaking)? onSpeakingChanged;

  bool get isSpeaking => _speaking;

  void _setSpeaking(bool value) {
    if (_speaking == value) return;
    _speaking = value;
    try {
      onSpeakingChanged?.call(value);
    } catch (e) {
      debugPrint('SiaVoice speaking callback error: $e');
    }
  }

  Future<void> init() async {
    if (_ready) return;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      _player.onPlayerComplete.listen((_) => _setSpeaking(false));

      if (_deviceTtsSupported) {
        try {
          final tts = FlutterTts();
          _tts = tts;
          await tts.setSpeechRate(0.46);
          await tts.setPitch(1.05);
          await tts.setVolume(1.0);
          await tts.awaitSpeakCompletion(true);
          await _pickFemaleVoice(tts);
          tts.setStartHandler(() => _setSpeaking(true));
          tts.setCompletionHandler(() => _setSpeaking(false));
          tts.setCancelHandler(() => _setSpeaking(false));
          tts.setErrorHandler((msg) {
            debugPrint('SiaVoice device TTS error: $msg');
            _setSpeaking(false);
          });
          _deviceTtsOk = true;
        } catch (e) {
          debugPrint('SiaVoice device TTS init failed: $e');
          _tts = null;
          _deviceTtsOk = false;
        }
      }
    } catch (e) {
      debugPrint('SiaVoice init warning: $e');
    }
    _ready = true;
  }

  Future<void> _pickFemaleVoice(FlutterTts tts) async {
    try {
      final voices = await tts.getVoices;
      if (voices is! List || voices.isEmpty) return;

      Map<String, dynamic>? chosen;
      for (final raw in voices) {
        final v = Map<String, dynamic>.from(raw as Map);
        final name = (v['name'] ?? '').toString().toLowerCase();
        final locale = (v['locale'] ?? '').toString().toLowerCase();
        if (!locale.startsWith('en')) continue;
        if (name.contains('zira') ||
            name.contains('samantha') ||
            name.contains('jenny') ||
            name.contains('karen') ||
            name.contains('victoria') ||
            name.contains('female') ||
            name.contains('aria') ||
            name.contains('hazel') ||
            name.contains('susan') ||
            name.contains('eva')) {
          chosen = v;
          break;
        }
      }
      if (chosen != null) {
        await tts.setVoice({
          'name': chosen['name'].toString(),
          'locale': chosen['locale'].toString(),
        });
      } else {
        await tts.setLanguage('en-US');
      }
    } catch (e) {
      debugPrint('SiaVoice TTS voice pick failed: $e');
    }
  }

  String cleanForSpeech(String text) {
    var t = text;
    t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    t = t.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    t = t.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    t = t.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
    t = t.replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 1400) {
      t = '${t.substring(0, 1400).trim()}...';
    }
    return t;
  }

  Future<void> speak(String text, {String language = 'english'}) async {
    final cleaned = cleanForSpeech(text);
    if (cleaned.isEmpty) return;

    var started = false;
    try {
      await init();
      await stop();
      _setSpeaking(true);

      // Windows: prefer built-in SAPI (fast, no native crash). Cloud next.
      if (Platform.isWindows) {
        final local = await _speakWindowsSapi(cleaned);
        if (local) {
          started = true;
          return;
        }
      }

      try {
        final bytes = await ApiService().fetchVoiceAudio(
          cleaned,
          language: language,
        );
        if (bytes != null && bytes.isNotEmpty) {
          final played = await _playMp3Bytes(bytes);
          if (played) {
            started = true;
            return;
          }
        }
      } catch (e) {
        debugPrint('SiaVoice cloud TTS failed: $e');
      }

      final tts = _tts;
      if (_deviceTtsOk && tts != null) {
        try {
          await tts.speak(cleaned);
          started = true;
          return;
        } catch (e) {
          debugPrint('SiaVoice device TTS failed: $e');
        }
      }
    } catch (e) {
      debugPrint('SiaVoice speak failed: $e');
    } finally {
      if (!started) _setSpeaking(false);
    }
  }

  /// Windows Speech API → temp WAV → AudioPlayer (avoids flutter_tts crash).
  Future<bool> _speakWindowsSapi(String text) async {
    try {
      final dir = await getTemporaryDirectory();
      final wavPath =
          '${dir.path}\\sia_win_${DateTime.now().millisecondsSinceEpoch}.wav';
      final safeText = text
          .replaceAll("'", "''")
          .replaceAll('\r', ' ')
          .replaceAll('\n', ' ');
      final safePath = wavPath.replaceAll("'", "''");
      final script = [
        "Add-Type -AssemblyName System.Speech",
        "\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer",
        "\$s.Rate = -1",
        "\$s.SetOutputToWaveFile('$safePath')",
        "\$s.Speak('$safeText')",
        "\$s.Dispose()",
      ].join('; ');
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      );
      if (result.exitCode != 0) {
        debugPrint('Windows SAPI exit ${result.exitCode}: ${result.stderr}');
        return false;
      }
      final file = File(wavPath);
      if (!await file.exists() || await file.length() == 0) return false;
      await _player.play(DeviceFileSource(wavPath));
      return true;
    } catch (e) {
      debugPrint('Windows SAPI speak failed: $e');
      return false;
    }
  }

  Future<bool> _playMp3Bytes(Uint8List bytes) async {
    try {
      if (Platform.isWindows || Platform.isLinux) {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/sia_voice_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(bytes, flush: true);
        await _player.play(DeviceFileSource(file.path));
      } else {
        await _player.play(BytesSource(bytes));
      }
      return true;
    } catch (e) {
      debugPrint('SiaVoice audio play failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    _setSpeaking(false);
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
