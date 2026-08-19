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
  List<dynamic> _videos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(title: const Text('Video Tutorials')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _videos.isEmpty
                  ? const Center(
                      child: Text('No video tutorials yet. Admin will post lessons here.'),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _videos.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final v = _videos[i] as Map;
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.play_circle_fill)),
                              title: Text(
                                '${v['title'] ?? 'Video'}',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text('${v['subject'] ?? 'Tutorial'}'),
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () => _open('${v['video_url'] ?? ''}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
