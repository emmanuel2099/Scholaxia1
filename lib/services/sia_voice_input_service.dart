import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Handles microphone permission + speech-to-text for Sia voice chat.
class SiaVoiceInputService {
  SiaVoiceInputService._();
  static final instance = SiaVoiceInputService._();

  final _speech = SpeechToText();
  bool _initialized = false;
  String _lastWords = '';
  bool _finalSent = false;
  void Function(String finalText)? _onFinal;
  void Function(String status)? _onStatus;

  String get lastWords => _lastWords;

  Future<bool> ensureReady(BuildContext context) async {
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Allow microphone access to use voice chat.'),
          ),
        );
      }
      return false;
    }

    if (!_initialized) {
      _initialized = await _speech.initialize(
        onError: (err) => debugPrint('SiaVoiceInput error: $err'),
        onStatus: (status) {
          _onStatus?.call(status);
          if ((status == 'done' || status == 'notListening') && !_finalSent) {
            final words = _lastWords.trim();
            if (words.isNotEmpty) {
              _finalSent = true;
              _onFinal?.call(words);
            }
          }
        },
      );
    }

    if (!_initialized && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice input is not available on this device. Type your question instead.',
          ),
        ),
      );
    }
    return _initialized;
  }

  Future<void> startListening({
    required void Function(String partial) onPartial,
    required void Function(String finalText) onFinal,
    void Function(String status)? onStatus,
  }) async {
    _lastWords = '';
    _finalSent = false;
    _onFinal = onFinal;
    _onStatus = onStatus;

    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isNotEmpty) {
          _lastWords = words;
          onPartial(words);
        }
        if (result.finalResult && words.isNotEmpty && !_finalSent) {
          _finalSent = true;
          onFinal(words);
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 60),
        localeId: 'en_US',
        cancelOnError: false,
      ),
    );
  }

  Future<String> stopAndCapture() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    await Future.delayed(const Duration(milliseconds: 350));
    return _lastWords.trim();
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  bool get isListening => _speech.isListening;
}
