import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';

class VideoTutorialsScreen extends StatefulWidget {
  const VideoTutorialsScreen({super.key});

  @override
  State<VideoTutorialsScreen> createState() => _VideoTutorialsScreenState();
}

class _VideoTutorialsScreenState extends State<VideoTutorialsScreen> {
  final _api = ApiService();
  final _searchController = TextEditingController();
  List<dynamic> _videos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _api.videoTutorials();
      if (!mounted) return;
      setState(() {
        _videos = rows;
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

  List<dynamic> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _videos;
    return _videos.where((raw) {
      final v = raw is Map ? raw : <String, dynamic>{};
      final blob = [
        v['title'],
        v['subject'],
        v['topic'],
        v['tutor_name'],
        v['tutor'],
        v['teacher_name'],
        v['channel'],
        v['exam_type'],
      ].whereType<Object>().join(' ').toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(title: const Text('Lesson Notes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search by topic or tutor name…',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? Center(
                              child: Text(
                                _searchController.text.trim().isEmpty
                                    ? 'No lesson notes yet. Admin will post lessons here.'
                                    : 'No lesson notes match your search.',
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) {
                                  final v = rows[i] as Map;
                                  final tutor = (v['tutor_name'] ??
                                          v['tutor'] ??
                                          v['teacher_name'] ??
                                          '')
                                      .toString()
                                      .trim();
                                  return Card(
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        child: Icon(Icons.play_circle_fill),
                                      ),
                                      title: Text(
                                        '${v['title'] ?? 'Lesson'}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: Text(
                                        [
                                          if ((v['subject'] ?? '')
                                              .toString()
                                              .trim()
                                              .isNotEmpty)
                                            '${v['subject']}',
                                          if (tutor.isNotEmpty) 'Tutor: $tutor',
                                        ].join(' · '),
                                      ),
                                      trailing: const Icon(Icons.open_in_new),
                                      onTap: () => _open(
                                        '${v['video_url'] ?? v['url'] ?? ''}',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}
