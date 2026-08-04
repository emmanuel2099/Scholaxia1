import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import '../api/api_service.dart';

/// Plays the Scholaxia ringtone for live class & group voice calls.
class LiveClassRingService {
  LiveClassRingService._();
  static final LiveClassRingService instance = LiveClassRingService._();

  static const assetPath = 'asset/sounds/live_class_ringtone.mp3';

  Timer? _ringTimer;
  bool _ringing = false;
  bool _stoppedByUser = false;
  AudioPlayer? _player;

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get isRinging => _ringing;

  Future<AudioPlayer> _ensurePlayer() async {
    _player ??= AudioPlayer();
    await _player!.setReleaseMode(ReleaseMode.stop);
    return _player!;
  }

  void stop() {
    _stoppedByUser = true;
    _ringTimer?.cancel();
    _ringTimer = null;
    _ringing = false;
    try {
      _player?.stop();
    } catch (_) {}
  }

  void resetStopFlag() => _stoppedByUser = false;

  /// Start ringing immediately (group call / live class invite).
  void startRingingNow() {
    if (_stoppedByUser) resetStopFlag();
    if (_ringing) return;
    _startRinging();
  }

  Future<void> syncWithLiveStatus(ApiService api) async {
    if (_stoppedByUser) return;
    try {
      final shouldRing = await _shouldRing(api);
      if (shouldRing && !_ringing) {
        _startRinging();
      } else if (!shouldRing && _ringing) {
        _ringTimer?.cancel();
        _ringTimer = null;
        _ringing = false;
        try {
          await _player?.stop();
        } catch (_) {}
        _stoppedByUser = false;
      }
    } catch (_) {}
  }

  Future<bool> _shouldRing(ApiService api) async {
    final codesData = await api.myAccessCodes();
    final codes = (codesData['codes'] as List?) ?? [];
    final hasUnreadCode = codes.any((raw) {
      if (raw is! Map) return false;
      if (raw['is_class_live'] == false) return false;
      return raw['is_read'] != true && raw['is_used'] != true;
    });
    if (hasUnreadCode) return true;

    final live = await api.listLiveClasses(status: 'live');
    if (live.any((c) => c is Map && c['is_live'] == true)) return true;

    final notifs = await api.notifications();
    return notifs.any((n) {
      if (n is! Map || n['is_read'] == true) return false;
      final t = (n['type']?.toString() ?? '').toLowerCase();
      if (!t.contains('live') && !t.contains('group_call')) return false;
      final title = (n['title']?.toString() ?? '').toLowerCase();
      final body = (n['body']?.toString() ?? '').toLowerCase();
      return !title.contains('ended') && !body.contains('has ended');
    });
  }

  void _startRinging() {
    _ringing = true;
    _playBurst();
    _ringTimer?.cancel();
    _ringTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_stoppedByUser) {
        stop();
        return;
      }
      _playBurst();
    });
  }

  void _playBurst() {
    // Always prefer the Scholaxia ringtone in asset/sounds/.
    // audioplayers prefixes AssetSource with "assets/" by default — clear that
    // so pubspec path `asset/sounds/live_class_ringtone.mp3` resolves correctly.
    unawaited(() async {
      try {
        AudioCache.instance = AudioCache(prefix: '');
        final p = await _ensurePlayer();
        await p.stop();
        await p.setVolume(1.0);
        await p.play(AssetSource(assetPath));
      } catch (_) {
        try {
          SystemSound.play(SystemSoundType.alert);
        } catch (_) {}
      }
    }());
  }
}
