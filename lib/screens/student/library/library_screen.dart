import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _books = [];
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.libraryStudentBooks();
      if (!mounted) return;
      setState(() {
        _books = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openBook(Map<String, dynamic> book) async {
    final id = book['id']?.toString() ?? '';
    if (id.isEmpty || _openingId != null) return;
    setState(() => _openingId = id);
    try {
      final detail = await _api.libraryReadBook(id);
      final url = detail['read_url']?.toString() ?? '';
      if (url.isEmpty) {
        throw ApiException.message('This book is not available to read yet.');
      }
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the book reader.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open book. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Text(
                    'Library',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Study materials uploaded by Scholaxia. Tap a book to read in-app (no download).',
                style: TextStyle(color: context.greyColor, fontSize: 13, height: 1.4),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child:
                          CircularProgressIndicator(color: context.accentColor))
                  : RefreshIndicator(
                      color: context.accentColor,
                      onRefresh: _load,
                      child: _books.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 80),
                                Icon(Icons.menu_book_outlined,
                                    size: 48, color: context.greyColor),
                                const SizedBox(height: 12),
                                Text(
                                  'No books yet',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.textColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Admin will add materials to your library soon.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: context.greyColor, fontSize: 13),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                              itemCount: _books.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                final b = _books[i];
                                final title = b['title']?.toString() ?? 'Book';
                                final author = b['author']?.toString() ?? '';
                                final subject = b['subject']?.toString() ?? '';
                                final cover = b['cover_image_url']?.toString();
                                final free = b['is_free'] != false;
                                final opening =
                                    _openingId == b['id']?.toString();
                                return Material(
                                  color: context.cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: opening ? null : () => _openBook(b),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: context.borderColor),
                                      ),
                                      child: Row(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Container(
                                              width: 56,
                                              height: 72,
                                              color: context.accentColor
                                                  .withOpacity(0.12),
                                              child: cover != null &&
                                                      cover.isNotEmpty
                                                  ? Image.network(
                                                      cover,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) =>
                                                          Icon(
                                                              Icons
                                                                  .menu_book_rounded,
                                                              color: context
                                                                  .accentColor),
                                                    )
                                                  : Icon(Icons.menu_book_rounded,
                                                      color:
                                                          context.accentColor),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: TextStyle(
                                                    color: context.textColor,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                if (author.isNotEmpty)
                                                  Text(author,
                                                      style: TextStyle(
                                                          color: context
                                                              .greyColor,
                                                          fontSize: 12)),
                                                const SizedBox(height: 4),
                                                Text(
                                                  [
                                                    if (subject.isNotEmpty)
                                                      subject,
                                                    free ? 'Free' : 'Paid',
                                                  ].join(' · '),
                                                  style: TextStyle(
                                                    color: context.accentColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (opening)
                                            const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          else
                                            Icon(Icons.chevron_right_rounded,
                                                color: context.greyColor),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
