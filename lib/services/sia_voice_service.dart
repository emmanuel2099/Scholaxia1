import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  bool get isSpeaking => _speaking;

  Future<void> init() async {
    if (_ready) return;
    await _tts.setSpeechRate(0.46);
    await _tts.setPitch(1.08);
    await _tts.setVolume(1.0);
    await _pickFemaleVoice();
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _player.onPlayerComplete.listen((_) => _speaking = false);
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
            name.contains('aria')) {
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
    } catch (_) {}
  }

  String cleanForSpeech(String text) {
    var t = text;
    t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    t = t.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    t = t.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    t = t.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
    t = t.replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > 3000) {
      t = '${t.substring(0, 3000).trim()}...';
    }
    return t;
  }

  Future<void> speak(String text, {String language = 'english'}) async {
    final cleaned = cleanForSpeech(text);
    if (cleaned.isEmpty) return;

    await init();
    await stop();
    _speaking = true;

    try {
      final bytes = await ApiService().fetchVoiceAudio(
        cleaned,
        language: language,
      );
      if (bytes != null && bytes.isNotEmpty) {
        await _player.play(BytesSource(bytes));
        return;
      }
    } catch (_) {}

    await _tts.speak(cleaned);
  }

  Future<void> stop() async {
    _speaking = false;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
