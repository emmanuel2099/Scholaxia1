import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Handles microphone permission + speech-to-text for Sia voice chat.
class SiaVoiceInputService {
  SiaVoiceInputService._();
  static final instance = SiaVoiceInputService._();

  /// Windows plugin crashes app (native thread bug). Use text input on desktop.
  static bool get isMicSupported =>
      !Platform.isWindows && !Platform.isLinux;

  final _speech = SpeechToText();
  bool _initialized = false;
  String _lastWords = '';
  int _session = 0;

  String get lastWords => _lastWords;

  Future<bool> ensureReady(BuildContext context) async {
    if (!isMicSupported) return false;

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
        onError: (_) {},
        onStatus: (_) {},
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

  void _runOnUi(void Function() fn) {
    SchedulerBinding.instance.scheduleFrameCallback((_) => fn());
  }

  Future<void> startListening({
    required void Function(String partial) onPartial,
    void Function(String finalText)? onFinal,
  }) async {
    if (!isMicSupported) return;

    _session++;
    final session = _session;
    _lastWords = '';

    if (_speech.isListening) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    await _speech.listen(
      onResult: (result) {
        if (session != _session) return;
        _runOnUi(() {
          if (session != _session) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _lastWords = words;
            onPartial(words);
          }
          if (onFinal != null && result.finalResult && words.isNotEmpty) {
            onFinal(words);
          }
        });
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(seconds: 60),
        localeId: 'en_US',
        cancelOnError: false,
      ),
    );
  }

  Future<String> stopAndCapture() async {
    if (!isMicSupported) return '';
    if (_speech.isListening) {
      await _speech.stop();
    }
    _session++;
    await Future.delayed(const Duration(milliseconds: 400));
    return _lastWords.trim();
  }

  Future<void> stop() async {
    _session++;
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  bool get isListening => _speech.isListening;
}
