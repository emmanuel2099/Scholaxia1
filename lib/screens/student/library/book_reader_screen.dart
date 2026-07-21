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
    required this.signedUrl,
    this.initialPage = 1,
  });

  final String bookId;
  final String title;
  final String signedUrl;
  final int initialPage;

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  final _api = ApiService();
  String? _path;
  String? _error;
  bool _saving = false;
  Timer? _progressDebounce;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final saved = await BookOfflineStore.instance.savedPath(widget.bookId);
    if (!mounted) return;
    setState(() {
      _path = saved;
      if (saved == null && widget.signedUrl.trim().isEmpty) {
        _error = 'This book is not available offline yet.';
      }
    });
  }

  Future<void> _saveOffline() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final path = await BookOfflineStore.instance.saveFromUrl(
        bookId: widget.bookId,
        signedUrl: widget.signedUrl,
      );
      if (!mounted) return;
      setState(() => _path = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved securely inside Scholaxia for offline reading.'),
        ),
      );
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
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: _path == null ? 'Save in app' : 'Saved in app',
              onPressed: _path == null ? _saveOffline : null,
              icon: Icon(
                _path == null
                    ? Icons.download_for_offline_outlined
                    : Icons.offline_pin_rounded,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: _path != null
                ? PdfViewer.file(
                    _path!,
                    initialPageNumber: widget.initialPage,
                    params: PdfViewerParams(onPageChanged: _saveProgress),
                  )
                : widget.signedUrl.trim().isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : PdfViewer.uri(
                        Uri.parse(widget.signedUrl),
                        initialPageNumber: widget.initialPage,
                        params: PdfViewerParams(onPageChanged: _saveProgress),
                      ),
          ),
        ],
      ),
    );
  }
}
