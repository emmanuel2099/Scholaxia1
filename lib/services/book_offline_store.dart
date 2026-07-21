import 'dart:io';

import 'package:http/http.dart' as http;
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

  Future<String> saveFromUrl({
    required String bookId,
    required String signedUrl,
  }) async {
    final response = await http.get(Uri.parse(signedUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Could not save this book for offline reading.');
    }
    final file = await _file(bookId);
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<void> remove(String bookId) async {
    final file = await _file(bookId);
    if (await file.exists()) await file.delete();
  }
}
