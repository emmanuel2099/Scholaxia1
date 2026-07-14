import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Caches downloaded CBT packs so students can practise offline.
class CbtOfflineStore {
  CbtOfflineStore._();
  static final instance = CbtOfflineStore._();

  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final d = Directory('${root.path}/cbt_offline');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String examId) async {
    final d = await _dir();
    return File('${d.path}/$examId.json');
  }

  Future<void> savePack(String examId, Map<String, dynamic> pack) async {
    final f = await _file(examId);
    await f.writeAsString(jsonEncode(pack));
  }

  Future<Map<String, dynamic>?> loadPack(String examId) async {
    final f = await _file(examId);
    if (!await f.exists()) return null;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }

  Future<bool> isDownloaded(String examId) async {
    final f = await _file(examId);
    return f.exists();
  }

  Future<Set<String>> downloadedIds() async {
    final d = await _dir();
    final out = <String>{};
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.json')) {
        out.add(e.uri.pathSegments.last.replaceAll('.json', ''));
      }
    }
    return out;
  }
}
