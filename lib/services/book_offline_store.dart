import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Keeps purchased/readable PDFs in the app's private documents directory.
///
/// Files are never written to Downloads or exposed through a share intent.
class BookOfflineStore {
  BookOfflineStore._();

  static final BookOfflineStore instance = BookOfflineStore._();

  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}library');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _file(String bookId) async {
    final directory = await _directory();
    final safeId = bookId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${directory.path}${Platform.pathSeparator}$safeId.pdf');
  }

  Future<String?> savedPath(String bookId) async {
    final file = await _file(bookId);
    return await file.exists() ? file.path : null;
  }

  Future<String> saveFromBytes({
    required String bookId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Empty PDF.');
    }
    final file = await _file(bookId);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Public device copy for books the admin marked downloadable.
  Future<String> saveUserDownload({
    required String title,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Empty PDF.');
    }
    final safe = title.replaceAll(RegExp(r'[^\w\s.-]'), '_').trim();
    final name = '${safe.isEmpty ? 'Scholaxia' : safe}.pdf';
    Directory dir;
    try {
      dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = await getApplicationDocumentsDirectory();
    }
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Session cache for online reading (not the permanent offline library).
  Future<String> writeTemp({
    required String bookId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Empty PDF.');
    }
    final root = await getTemporaryDirectory();
    final safeId = bookId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(
      '${root.path}${Platform.pathSeparator}scholaxia_lib_$safeId.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> remove(String bookId) async {
    final file = await _file(bookId);
    if (await file.exists()) await file.delete();
  }
}
