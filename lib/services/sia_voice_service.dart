import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_service.dart';

/// Speaks Sia / Teacher AI replies with a clear female voice.
/// Tries cloud TTS (ElevenLabs) first, then device TTS fallback.
class SiaVoiceService {
  SiaVoiceService._();
  static final instance = SiaVoiceService._();

  final _player = AudioPlayer();
  final _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;
  void Function(bool speaking)? onSpeakingChanged;

  bool get isSpeaking => _speaking;

  void _setSpeaking(bool value) {
    _speaking = value;
    onSpeakingChanged?.call(value);
  }

  Future<void> init() async {
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    await _tts.setSpeechRate(0.46);
    await _tts.setPitch(1.08);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    await _pickFemaleVoice();
    _tts.setStartHandler(() => _setSpeaking(true));
    _tts.setCompletionHandler(() => _setSpeaking(false));
    _tts.setCancelHandler(() => _setSpeaking(false));
    _tts.setErrorHandler((_) => _setSpeaking(false));
    _player.onPlayerComplete.listen((_) => _setSpeaking(false));
    _ready = true;
  }

  Future<void> _pickFemaleVoice() async {
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
      chosen ??= voices
          .map((e) => Map<String, dynamic>.from(e as Map))
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (v) => (v!['locale'] ?? '').toString().toLowerCase().startsWith('en'),
            orElse: () => Map<String, dynamic>.from(voices.first as Map),
          );
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

    await init();
    await stop();
    _setSpeaking(true);

    // Cloud voice first (ElevenLabs female voice on server)
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

    // Device TTS fallback (Windows Zira / mobile voices)
    try {
      await _tts.speak(cleaned);
    } catch (e) {
      debugPrint('SiaVoice device TTS failed: $e');
      _setSpeaking(false);
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
      _setSpeaking(false);
      return false;
    }
  }

  Future<void> stop() async {
    _setSpeaking(false);
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
