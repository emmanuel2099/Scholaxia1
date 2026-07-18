import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../api/api_service.dart';

/// Client-side anti-cheat sensors for Scholaxia Intellect League (PRD §18).
/// Server remains the source of truth for pause / forfeit / human review.
class SilAntiCheatService {
  SilAntiCheatService._();
  static final instance = SilAntiCheatService._();

  final _api = ApiService();

  /// Root / jailbreak / emulator heuristics + report to server.
  Future<Map<String, dynamic>> runDeviceGate({String? matchId}) async {
    final report = await inspectDevice();
    try {
      return await _api.silDeviceReport(
        isEmulator: report.isEmulator,
        isRooted: report.isRooted,
        isJailbroken: report.isJailbroken,
        platform: report.platform,
        model: report.model,
        matchId: matchId,
        raw: report.raw,
      );
    } catch (_) {
      // Offline: block locally if clearly risky
      final allowed = !(report.isEmulator || report.isRooted || report.isJailbroken);
      return {
        'allowed': allowed,
        'reason': allowed
            ? null
            : (report.isEmulator
                ? 'emulator'
                : (report.isRooted ? 'rooted' : 'jailbroken')),
        'offline': true,
      };
    }
  }

  Future<SilDeviceIntegrity> inspectDevice() async {
    final raw = <String, dynamic>{
      'kIsWeb': kIsWeb,
      'kDebugMode': kDebugMode,
    };

    if (kIsWeb) {
      return SilDeviceIntegrity(
        isEmulator: false,
        isRooted: false,
        isJailbroken: false,
        platform: 'web',
        model: 'browser',
        raw: raw,
      );
    }

    String platform = 'unknown';
    String model = 'unknown';
    var emulator = false;
    var rooted = false;
    var jailbroken = false;

    try {
      if (Platform.isAndroid) {
        platform = 'android';
        // Emulator heuristics
        final env = Platform.environment;
        raw['env_keys'] = env.keys.take(20).toList();
        final finger = (env['FINGERPRINT'] ?? env['ANDROID_FINGERPRINT'] ?? '')
            .toLowerCase();
        final modelEnv = (env['MODEL'] ?? '').toLowerCase();
        final product = (env['PRODUCT'] ?? '').toLowerCase();
        final hardware = (env['HARDWARE'] ?? '').toLowerCase();
        model = modelEnv.isNotEmpty ? modelEnv : product;
        emulator = _looksLikeEmulator(
            finger: finger, model: modelEnv, product: product, hardware: hardware);
        rooted = await _androidRootHints();
        raw['emulator_hints'] = emulator;
        raw['root_hints'] = rooted;
      } else if (Platform.isIOS) {
        platform = 'ios';
        model = Platform.operatingSystemVersion;
        jailbroken = await _iosJailbreakHints();
        // iOS simulator
        emulator = Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') ||
            Platform.environment.containsKey('SIMULATOR_UDID');
        raw['jailbreak_hints'] = jailbroken;
        raw['simulator'] = emulator;
      } else if (Platform.isWindows) {
        platform = 'windows';
        model = Platform.localHostname;
        // Desktop is allowed for practice/dev but flagged as elevated risk for live bets
        raw['desktop'] = true;
      } else if (Platform.isMacOS) {
        platform = 'macos';
        model = Platform.localHostname;
        raw['desktop'] = true;
      } else if (Platform.isLinux) {
        platform = 'linux';
        model = Platform.localHostname;
        raw['desktop'] = true;
      }
    } catch (e) {
      raw['inspect_error'] = e.toString();
    }

    return SilDeviceIntegrity(
      isEmulator: emulator,
      isRooted: rooted,
      isJailbroken: jailbroken,
      platform: platform,
      model: model,
      raw: raw,
    );
  }

  bool _looksLikeEmulator({
    required String finger,
    required String model,
    required String product,
    required String hardware,
  }) {
    const marks = [
      'generic',
      'emulator',
      'sdk_gphone',
      'google_sdk',
      'droid4x',
      'genymotion',
      'vbox',
      'goldfish',
      'ranchu',
      'ttvm',
      'nox',
    ];
    final blob = '$finger $model $product $hardware';
    return marks.any(blob.contains);
  }

  Future<bool> _androidRootHints() async {
    // Best-effort path checks (may be blocked on modern Android — still useful signal)
    const paths = [
      '/system/app/Superuser.apk',
      '/sbin/su',
      '/system/bin/su',
      '/system/xbin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
      '/data/local/su',
      '/su/bin/su',
    ];
    for (final p in paths) {
      try {
        if (await File(p).exists()) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<bool> _iosJailbreakHints() async {
    const paths = [
      '/Applications/Cydia.app',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash',
      '/usr/sbin/sshd',
      '/etc/apt',
      '/private/var/lib/apt/',
    ];
    for (final p in paths) {
      try {
        if (await File(p).exists()) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<Map<String, dynamic>> reportEvent(
    String matchId,
    String eventType, {
    String? detail,
    Map<String, dynamic>? meta,
  }) async {
    try {
      return await _api.silAnticheat(
        matchId,
        eventType,
        detail: detail,
        meta: meta,
      );
    } catch (_) {
      return {
        'logged': false,
        'forfeited': eventType == 'emulator' ||
            eventType == 'rooted' ||
            eventType == 'jailbroken',
        'paused': eventType == 'background',
      };
    }
  }

  Future<Map<String, dynamic>> heartbeat(
    String matchId, {
    required bool faceInFrame,
    required int faceCount,
    double? luminance,
    String? detail,
  }) async {
    try {
      return await _api.silHeartbeat(
        matchId,
        faceInFrame: faceInFrame,
        faceCount: faceCount,
        luminance: luminance,
        detail: detail,
      );
    } catch (_) {
      return {'ok': faceInFrame && faceCount == 1};
    }
  }

  /// Suspicious timing: many answers under 800ms suggests auto-tap / remote assist.
  bool looksSuspiciousTiming(List<Map<String, dynamic>> answers) {
    if (answers.length < 3) return false;
    final fast = answers
        .where((a) => ((a['elapsed_ms'] as num?)?.toInt() ?? 9999) < 800)
        .length;
    return fast >= (answers.length * 0.6).ceil();
  }
}

class SilDeviceIntegrity {
  final bool isEmulator;
  final bool isRooted;
  final bool isJailbroken;
  final String platform;
  final String model;
  final Map<String, dynamic> raw;

  const SilDeviceIntegrity({
    required this.isEmulator,
    required this.isRooted,
    required this.isJailbroken,
    required this.platform,
    required this.model,
    required this.raw,
  });

  bool get isRisky => isEmulator || isRooted || isJailbroken;
}
