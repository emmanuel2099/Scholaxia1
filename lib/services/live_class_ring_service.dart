import 'dart:async';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../api/api_service.dart';

/// Plays the system default ringtone when a live class is hosted (like desktop).
class LiveClassRingService {
  LiveClassRingService._();
  static final LiveClassRingService instance = LiveClassRingService._();

  Timer? _ringTimer;
  bool _ringing = false;
  bool _stoppedByUser = false;

  bool get isRinging => _ringing;

  void stop() {
    _stoppedByUser = true;
    _ringTimer?.cancel();
    _ringTimer = null;
    _ringing = false;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }

  void resetStopFlag() => _stoppedByUser = false;

  Future<void> syncWithLiveStatus(ApiService api) async {
    if (_stoppedByUser) return;
    try {
      final live = await api.listLiveClasses(status: 'live');
      final notifs = await api.notifications();
      final hasLiveNotif = notifs.any((n) {
        if (n is! Map || n['is_read'] == true) return false;
        final t = (n['type']?.toString() ?? '').toLowerCase();
        final title = (n['title']?.toString() ?? '').toLowerCase();
        final body = (n['body']?.toString() ?? '').toLowerCase();
        if (t.contains('live')) {
          if (body.contains('has ended') || title.contains('ended')) return false;
          return true;
        }
        return false;
      });
      final shouldRing = live.isNotEmpty && hasLiveNotif;
      if (shouldRing && !_ringing) {
        _startRinging();
      } else if (!shouldRing && _ringing) {
        stop();
        _stoppedByUser = false;
      }
    } catch (_) {}
  }

  void _startRinging() {
    _ringing = true;
    _playBurst();
    _ringTimer?.cancel();
    _ringTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (_stoppedByUser) {
        stop();
        return;
      }
      _playBurst();
    });
  }

  void _playBurst() {
    try {
      FlutterRingtonePlayer().playRingtone(
        looping: false,
        volume: 1.0,
        asAlarm: false,
      );
    } catch (_) {}
  }
}
