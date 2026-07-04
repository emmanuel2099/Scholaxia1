import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../api/api_service.dart';

/// Plays a ringtone when a live class is hosted (like desktop notifications-ui.js).
class LiveClassRingService {
  LiveClassRingService._();
  static final LiveClassRingService instance = LiveClassRingService._();

  Timer? _ringTimer;
  bool _ringing = false;
  bool _stoppedByUser = false;

  static bool get _useMobileRingtone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get isRinging => _ringing;

  void stop() {
    _stoppedByUser = true;
    _ringTimer?.cancel();
    _ringTimer = null;
    _ringing = false;
    if (_useMobileRingtone) {
      try {
        FlutterRingtonePlayer().stop();
      } catch (_) {}
    }
  }

  void resetStopFlag() => _stoppedByUser = false;

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
        if (_useMobileRingtone) {
          try {
            FlutterRingtonePlayer().stop();
          } catch (_) {}
        }
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
      if (!t.contains('live')) return false;
      final title = (n['title']?.toString() ?? '').toLowerCase();
      final body = (n['body']?.toString() ?? '').toLowerCase();
      return !title.contains('ended') && !body.contains('has ended');
    });
  }

  void _startRinging() {
    _ringing = true;
    _playBurst();
    _ringTimer?.cancel();
    _ringTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_stoppedByUser) {
        stop();
        return;
      }
      _playBurst();
    });
  }

  void _playBurst() {
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    if (!_useMobileRingtone) return;
    try {
      FlutterRingtonePlayer().playRingtone(
        looping: false,
        volume: 1.0,
        asAlarm: true,
      );
    } catch (_) {}
  }
}
