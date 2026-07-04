import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_service.dart';

/// Speaks Sia / Teacher AI replies with a clear female voice.
/// Windows: cloud MP3 only (device TTS disabled — avoids native crashes).
class SiaVoiceService {
  SiaVoiceService._();
  static final instance = SiaVoiceService._();

  final _player = AudioPlayer();
  final _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;
  void Function(bool speaking)? onSpeakingChanged;

  bool get isSpeaking => _speaking;

  static bool get _useDeviceTts => !Platform.isWindows && !Platform.isLinux;

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

      if (_useDeviceTts) {
        await _tts.setSpeechRate(0.46);
        await _tts.setPitch(1.08);
        await _tts.setVolume(1.0);
        await _tts.awaitSpeakCompletion(true);
        await _pickFemaleVoice();
        _tts.setStartHandler(() => _setSpeaking(true));
        _tts.setCompletionHandler(() => _setSpeaking(false));
        _tts.setCancelHandler(() => _setSpeaking(false));
        _tts.setErrorHandler((_) => _setSpeaking(false));
      }
    } catch (e) {
      debugPrint('SiaVoice init warning: $e');
    }
    _ready = true;
  }

  Future<void> _pickFemaleVoice() async {
    if (!_useDeviceTts) return;
    try {
      final voices = await _tts.getVoices;
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
            name.contains('hazel')) {
          chosen = v;
          break;
        }
      }
      if (chosen != null) {
        await _tts.setVoice({
          'name': chosen['name'],
          'locale': chosen['locale'],
        });
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
    if (t.length > 1200) {
      t = '${t.substring(0, 1200).trim()}...';
    }
    return t;
  }

  Future<void> speak(String text, {String language = 'english'}) async {
    final cleaned = cleanForSpeech(text);
    if (cleaned.isEmpty) return;

    try {
      await init();
      await stop();
      _setSpeaking(true);

      try {
        final bytes = await ApiService().fetchVoiceAudio(
          cleaned,
          language: language,
        );
        if (bytes != null && bytes.isNotEmpty) {
          final played = await _playMp3Bytes(bytes);
          if (played) return;
        }
      } catch (e) {
        debugPrint('SiaVoice cloud TTS failed: $e');
      }

      if (_useDeviceTts) {
        try {
          await _tts.speak(cleaned);
          return;
        } catch (e) {
          debugPrint('SiaVoice device TTS failed: $e');
        }
      }
    } catch (e) {
      debugPrint('SiaVoice speak failed: $e');
    } finally {
      if (Platform.isWindows || Platform.isLinux) {
        _setSpeaking(false);
      }
    }
  }

  Future<bool> _playMp3Bytes(Uint8List bytes) async {
    try {
      if (Platform.isWindows || Platform.isLinux) {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/sia_voice_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(bytes);
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
    if (_useDeviceTts) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
  }
}
