import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../api/api_service.dart';
import '../../../services/book_offline_store.dart';

class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({
    super.key,
    required this.bookId,
    required this.title,
    this.signedUrl = '',
    this.initialPage = 1,
    this.isDownloadable = false,
  });

  final String bookId;
  final String title;
  /// Unused for viewing — kept so older call sites still compile.
  final String signedUrl;
  final int initialPage;
  final bool isDownloadable;

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  final _api = ApiService();
  String? _path;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  Timer? _progressDebounce;

  bool get _isPermanentOffline {
    final path = _path;
    if (path == null) return false;
    return !path.contains('scholaxia_lib_');
  }

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await BookOfflineStore.instance.savedPath(widget.bookId);
      if (saved != null) {
        if (!mounted) return;
        setState(() {
          _path = saved;
          _loading = false;
        });
        return;
      }

      final bytes = await _api.libraryDownloadBook(widget.bookId);
      final path = await BookOfflineStore.instance.writeTemp(
        bookId: widget.bookId,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _path = path;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveOffline() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await _api.libraryDownloadBook(widget.bookId);
      final path = await BookOfflineStore.instance.saveFromBytes(
        bookId: widget.bookId,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _path = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved securely inside Scholaxia for offline reading.'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveToDevice() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await _api.libraryDownloadBook(
        widget.bookId,
        asAttachment: true,
      );
      final path = await BookOfflineStore.instance.saveUserDownload(
        title: widget.title,
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded to $path')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _saveProgress(int? page) {
    if (page == null) return;
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 800), () {
      _api.libraryUpdateProgress(widget.bookId, page);
    });
  }

  @override
  void dispose() {
    _progressDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_saving || _loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            if (widget.isDownloadable)
              IconButton(
                tooltip: 'Download PDF',
                onPressed: _path == null || _error != null
                    ? null
                    : _saveToDevice,
                icon: const Icon(Icons.download_rounded),
              ),
            IconButton(
              tooltip: _isPermanentOffline ? 'Saved in app' : 'Save in app',
              onPressed: (_path == null || _error != null || _isPermanentOffline)
                  ? null
                  : _saveOffline,
              icon: Icon(
                _isPermanentOffline
                    ? Icons.offline_pin_rounded
                    : Icons.download_for_offline_outlined,
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _prepare,
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _path != null
                    ? PdfViewer.file(
                        _path!,
                        initialPageNumber: widget.initialPage,
                        params: PdfViewerParams(onPageChanged: _saveProgress),
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error ?? 'This book is not available yet.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
