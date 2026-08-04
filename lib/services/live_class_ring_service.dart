import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import '../api/api_service.dart';

/// Plays the Scholaxia ringtone for live class & group voice calls.
///
/// Rings in short bursts with a hard time limit so it never loops forever
/// while a class stays live.
class LiveClassRingService {
  LiveClassRingService._();
  static final LiveClassRingService instance = LiveClassRingService._();

  static const assetPath = 'asset/sounds/live_class_ringtone.mp3';

  /// Max time the ringtone may keep playing for one invite wave.
  static const Duration maxRingDuration = Duration(seconds: 45);

  /// How often each burst plays while ringing.
  static const Duration burstInterval = Duration(seconds: 4);

  Timer? _ringTimer;
  Timer? _limitTimer;
  bool _ringing = false;
  bool _stoppedByUser = false;
  bool _limitReached = false;
  DateTime? _ringStartedAt;
  String? _lastInviteKey;
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
    _cancelTimers();
    _ringing = false;
    try {
      _player?.stop();
    } catch (_) {}
  }

  void resetStopFlag() {
    _stoppedByUser = false;
    _limitReached = false;
  }

  void _cancelTimers() {
    _ringTimer?.cancel();
    _ringTimer = null;
    _limitTimer?.cancel();
    _limitTimer = null;
  }

  /// Start ringing immediately (group call / live class invite).
  void startRingingNow({String? inviteKey}) {
    if (_stoppedByUser || _limitReached) return;
    if (inviteKey != null && inviteKey == _lastInviteKey && _limitReached) {
      return;
    }
    if (inviteKey != null) _lastInviteKey = inviteKey;
    if (_ringing) return;
    _startRinging();
  }

  Future<void> syncWithLiveStatus(ApiService api) async {
    if (_stoppedByUser) return;
    try {
      final invite = await _activeInviteKey(api);
      final shouldRing = invite != null;
      if (shouldRing && !_ringing && !_limitReached) {
        _lastInviteKey = invite;
        _startRinging();
      } else if (!shouldRing && _ringing) {
        _softStop();
      } else if (!shouldRing) {
        // New invite wave can ring again later.
        _limitReached = false;
      }
    } catch (_) {}
  }

  void _softStop() {
    _cancelTimers();
    _ringing = false;
    try {
      _player?.stop();
    } catch (_) {}
  }

  /// Only unread invites / live notifications — not "any class is live forever".
  Future<String?> _activeInviteKey(ApiService api) async {
    final codesData = await api.myAccessCodes();
    final codes = (codesData['codes'] as List?) ?? [];
    for (final raw in codes) {
      if (raw is! Map) continue;
      if (raw['is_class_live'] == false) continue;
      if (raw['is_read'] == true || raw['is_used'] == true) continue;
      final id = raw['id']?.toString() ??
          raw['code']?.toString() ??
          raw['access_code']?.toString() ??
          '';
      if (id.isNotEmpty) return 'code:$id';
    }

    final notifs = await api.notifications();
    for (final n in notifs) {
      if (n is! Map || n['is_read'] == true) continue;
      final t = (n['type']?.toString() ?? '').toLowerCase();
      if (!t.contains('live') && !t.contains('group_call')) continue;
      final title = (n['title']?.toString() ?? '').toLowerCase();
      final body = (n['body']?.toString() ?? '').toLowerCase();
      if (title.contains('ended') || body.contains('has ended')) continue;
      final id = n['id']?.toString() ?? '';
      if (id.isNotEmpty) return 'notif:$id';
      return 'notif:${title.hashCode}';
    }
    return null;
  }

  void _startRinging() {
    _ringing = true;
    _limitReached = false;
    _ringStartedAt = DateTime.now();
    _playBurst();
    _cancelTimers();
    _ringTimer = Timer.periodic(burstInterval, (_) {
      if (_stoppedByUser || _limitReached) {
        stop();
        return;
      }
      final started = _ringStartedAt;
      if (started != null &&
          DateTime.now().difference(started) >= maxRingDuration) {
        _hitLimit();
        return;
      }
      _playBurst();
    });
    _limitTimer = Timer(maxRingDuration, _hitLimit);
  }

  void _hitLimit() {
    _limitReached = true;
    _softStop();
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
