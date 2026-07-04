import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_live_class.dart';

/// Local storage for saved live class recordings (device only, like desktop IndexedDB).
class SavedLiveClassService {
  SavedLiveClassService._();
  static final instance = SavedLiveClassService._();

  static const _indexKey = 'saved_live_classes_v1';

  Future<Directory> _storageDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/saved_live_classes');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<SavedLiveClass>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final rows = decoded
          .whereType<Map>()
          .map((e) => SavedLiveClass.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.filePath.isNotEmpty && File(r.filePath).existsSync())
          .toList();
      rows.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return rows;
    } catch (_) {
      return [];
    }
  }

  Future<SavedLiveClass> save({
    required String title,
    required String subject,
    required String teacher,
    required String classId,
    required File sourceFile,
    String mediaType = 'audio',
    int? durationSeconds,
  }) async {
    final dir = await _storageDir();
    final id = 'live-${DateTime.now().millisecondsSinceEpoch}';
    final ext = sourceFile.path.split('.').last;
    final dest = File('${dir.path}/$id.$ext');
    await sourceFile.copy(dest.path);

    final row = SavedLiveClass(
      id: id,
      title: title.isNotEmpty ? title : 'Live class',
      subject: subject,
      teacher: teacher,
      classId: classId,
      savedAt: DateTime.now(),
      filePath: dest.path,
      mediaType: mediaType,
      durationSeconds: durationSeconds,
    );

    final rows = await list();
    rows.insert(0, row);
    await _writeIndex(rows);
    return row;
  }

  Future<void> delete(String id) async {
    final rows = await list();
    final row = rows.where((r) => r.id == id).firstOrNull;
    if (row != null) {
      final file = File(row.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    rows.removeWhere((r) => r.id == id);
    await _writeIndex(rows);
  }

  Future<void> _writeIndex(List<SavedLiveClass> rows) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(rows.map((r) => r.toJson()).toList());
    await prefs.setString(_indexKey, encoded);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
