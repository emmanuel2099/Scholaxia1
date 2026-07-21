import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/paystack_checkout_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'book_reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _fixedCategories = [
    'All',
    'Books',
    'Study Materials',
    'Scheme of Work',
  ];

  final _api = ApiService();
  final _searchController = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _books = [];
  String? _openingId;
  String _category = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _bookCategory(Map<String, dynamic> book) {
    final raw = (book['category']?.toString() ?? 'Books').trim();
    if (raw.toLowerCase().contains('scheme')) return 'Scheme of Work';
    if (raw.toLowerCase().contains('study') ||
        raw.toLowerCase().contains('note') ||
        raw.toLowerCase().contains('material')) {
      return 'Study Materials';
    }
    if (raw.toLowerCase().contains('past')) return 'Study Materials';
    return 'Books';
  }

  List<Map<String, dynamic>> get _searchMatched {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _books;
    return _books.where((book) {
      return [
        book['title'],
        book['author'],
        book['subject'],
        book['exam_type'],
        book['scheme_topic'],
        book['description'],
        _bookCategory(book),
      ].whereType<Object>().any(
        (value) => value.toString().toLowerCase().contains(q),
      );
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredBooks {
    final matched = _searchMatched;
    if (_category == 'All') return matched;
    return matched
        .where((book) => _bookCategory(book) == _category)
        .toList();
  }

  int _countFor(String category) {
    return _searchMatched
        .where((book) => _bookCategory(book) == category)
        .length;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.libraryStudentBooks(
        searchQuery: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
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
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookReaderScreen(
            bookId: id,
            title: detail['title']?.toString() ??
                book['title']?.toString() ??
                'Book',
            signedUrl: url,
            initialPage: (detail['current_page'] as num?)?.toInt() ?? 1,
          ),
        ),
      );
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

  void _showPurchaseRequired(Map<String, dynamic> book) {
    final price = (book['price'] as num?)?.toDouble() ?? 0;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unlock this material',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(book['title']?.toString() ?? 'Study material'),
            const SizedBox(height: 6),
            Text(
              '₦${price.toStringAsFixed(0)} · One-time purchase',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'After payment, you can save and read it inside Scholaxia without exporting the PDF to your phone.',
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _purchaseBook(book);
                },
                child: Text('Pay ₦${price.toStringAsFixed(0)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _purchaseBook(Map<String, dynamic> book) async {
    final id = book['id']?.toString() ?? '';
    if (id.isEmpty || _openingId != null) return;
    setState(() => _openingId = id);
    try {
      final paid = await PaystackCheckoutService.purchase(
        context: context,
        api: _api,
        productType: 'library_book',
        productId: id,
      );
      if (!mounted || !paid) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment confirmed. Book unlocked.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not complete payment. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'Study Materials':
        return Icons.description_rounded;
      case 'Scheme of Work':
        return Icons.calendar_view_week_rounded;
      default:
        return Icons.menu_book_rounded;
    }
  }

  String _emptyMessage() {
    if (_searchController.text.trim().isNotEmpty) {
      return 'No results for “${_searchController.text.trim()}”.';
    }
    switch (_category) {
      case 'Books':
        return 'No books yet. Admin will upload paid PDF books here.';
      case 'Study Materials':
        return 'No study materials yet. Admin will upload notes and materials here.';
      case 'Scheme of Work':
        return 'No scheme of work yet. Admin will upload weekly schemes here.';
      default:
        return 'Admin will add books, study materials and schemes of work soon.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleBooks = _filteredBooks;
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
                'Browse Books, Study Materials and Scheme of Work. Search stays live as you type.',
                style: TextStyle(
                  color: context.greyColor,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search books, study materials, scheme of work',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _fixedCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final category = _fixedCategories[index];
                  final selected = category == _category;
                  final count = category == 'All'
                      ? _searchMatched.length
                      : _countFor(category);
                  return ChoiceChip(
                    avatar: Icon(
                      category == 'All'
                          ? Icons.apps_rounded
                          : _iconFor(category),
                      size: 16,
                    ),
                    label: Text(
                      count > 0 ? '$category ($count)' : category,
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = category),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.accentColor,
                      ),
                    )
                  : RefreshIndicator(
                      color: context.accentColor,
                      onRefresh: _load,
                      child: visibleBooks.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                              children: [
                                const SizedBox(height: 48),
                                Icon(
                                  _category == 'All'
                                      ? Icons.menu_book_outlined
                                      : _iconFor(_category),
                                  size: 48,
                                  color: context.greyColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _category == 'All'
                                      ? 'No materials yet'
                                      : 'No $_category yet',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.textColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _emptyMessage(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.greyColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                              children: [
                                if (_category == 'All') ...[
                                  for (final section in const [
                                    'Books',
                                    'Study Materials',
                                    'Scheme of Work',
                                  ]) ...[
                                    if (_countFor(section) > 0) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8,
                                          bottom: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _iconFor(section),
                                              color: context.accentColor,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              section,
                                              style: TextStyle(
                                                color: context.textColor,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ..._searchMatched
                                          .where(
                                            (book) =>
                                                _bookCategory(book) == section,
                                          )
                                          .map(_materialTile),
                                      const SizedBox(height: 8),
                                    ],
                                  ],
                                ] else
                                  ...visibleBooks.map(_materialTile),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _materialTile(Map<String, dynamic> b) {
    final title = b['title']?.toString() ?? 'Book';
    final author = b['author']?.toString() ?? '';
    final subject = b['subject']?.toString() ?? '';
    final cover = b['cover_image_url']?.toString();
    final free = b['is_free'] != false;
    final hasAccess = b['has_access'] == true;
    final price = (b['price'] as num?)?.toDouble() ?? 0;
    final category = _bookCategory(b);
    final opening = _openingId == b['id']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: opening
              ? null
              : () => free || hasAccess
                  ? _openBook(b)
                  : _showPurchaseRequired(b),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 56,
                    height: 72,
                    color: context.accentColor.withValues(alpha: 0.12),
                    child: cover != null && cover.isNotEmpty
                        ? Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              _iconFor(category),
                              color: context.accentColor,
                            ),
                          )
                        : Icon(
                            _iconFor(category),
                            color: context.accentColor,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        Text(
                          author,
                          style: TextStyle(
                            color: context.greyColor,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (subject.isNotEmpty) subject,
                          category,
                          free
                              ? 'Free'
                              : hasAccess
                                  ? 'Purchased'
                                  : '₦${price.toStringAsFixed(0)}',
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    free || hasAccess
                        ? Icons.chevron_right_rounded
                        : Icons.lock_rounded,
                    color: free || hasAccess
                        ? context.greyColor
                        : context.accentColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
