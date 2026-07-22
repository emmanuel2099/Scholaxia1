import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Safe SharedPreferences access — recovers when the Windows JSON file is corrupt.
class AppPrefs {
  AppPrefs._();

  static Future<SharedPreferences>? _opening;

  static Future<SharedPreferences> instance() {
    final existing = _opening;
    if (existing != null) return existing;
    final future = _open();
    _opening = future;
    return future;
  }

  static Future<SharedPreferences> _open() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Force a read so a half-parsed corrupt store still surfaces.
      prefs.getKeys();
      return prefs;
    } on FormatException catch (e) {
      debugPrint('SharedPreferences corrupt, resetting: $e');
      await _resetWindowsPrefsFile();
      try {
        // Clear cached failed future from the plugin when available.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.resetStatic();
      } catch (_) {}
      _opening = null;
      final prefs = await SharedPreferences.getInstance();
      prefs.getKeys();
      return prefs;
    } catch (e) {
      _opening = null;
      rethrow;
    }
  }

  static Future<void> _resetWindowsPrefsFile() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final roaming = Platform.environment['APPDATA'];
      if (roaming == null || roaming.isEmpty) return;
      final candidates = <String>[
        '$roaming\\com.scholaxia\\scholaxia\\shared_preferences.json',
        '$roaming\\com.example\\scholaxia\\shared_preferences.json',
      ];
      for (final path in candidates) {
        final file = File(path);
        if (!await file.exists()) continue;
        try {
          await file.copy('$path.corrupt.bak');
        } catch (_) {}
        await file.writeAsString('{}', flush: true);
        debugPrint('Reset prefs file: $path');
      }
    } catch (e) {
      debugPrint('Could not reset prefs file: $e');
    }
  }
}

Future<void> ensurePrefsHealthy() async {
  try {
    await AppPrefs.instance();
  } catch (e) {
    debugPrint('ensurePrefsHealthy: $e');
  }
}
