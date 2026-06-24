import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../teacher_shared.dart';

class TeacherNoticesScreen extends StatefulWidget {
  const TeacherNoticesScreen({super.key});

  @override
  State<TeacherNoticesScreen> createState() => _TeacherNoticesScreenState();
}

class _TeacherNoticesScreenState extends State<TeacherNoticesScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _api = ApiService();
  bool _sending = false;
  bool _loading = true;
  String? _teacherName;
  int _unread = 0;
  String _announcementChannelId = '';
  String _announcementChannelName = 'Teacher Announcements';
  List<Map<String, dynamic>> _sent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final channels = await _api.communityChannels();
      for (final ch in channels) {
        if (ch is! Map) continue;
        final name = ch['name']?.toString().toLowerCase() ?? '';
        final type = ch['channel_type']?.toString().toLowerCase() ?? '';
        if (name.contains('announcement') ||
            name.contains('teacher') ||
            type.contains('announcement')) {
          _announcementChannelId = ch['id']?.toString() ?? '';
          _announcementChannelName = ch['name']?.toString() ?? _announcementChannelName;
          break;
        }
      }
      List<Map<String, dynamic>> posts = [];
      if (_announcementChannelId.isNotEmpty) {
        try {
          await _api.joinChannel(channelId: _announcementChannelId);
        } catch (_) {}
        final raw = await _api.listPosts(channelId: _announcementChannelId);
        posts = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      final profile = await _api.getTeacherMe();
      final unread = await _api.unreadNotificationCount();
      if (mounted) {
        setState(() {
          _teacherName = profile['full_name']?.toString();
          _unread = unread;
          _sent = posts;
          _loading = false;
        });
        teacherUnreadCount.value = unread;
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendNotice() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in title and body.')),
      );
      return;
    }
    if (_announcementChannelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement channel not found.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final content = '$title\n\n$body';
      final post = await _api.createPost(
        channelId: _announcementChannelId,
        content: content,
        isAnonymous: false,
        visibility: 'everyone',
      );
      _titleController.clear();
      _bodyController.clear();
      if (mounted) {
        setState(() {
          _sent = [Map<String, dynamic>.from(post), ..._sent];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement sent to all students!')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.yellow))
            : RefreshIndicator(
                color: AppColors.yellow,
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      TeacherTopBar(
                        api: _api,
                        teacherName: _teacherName,
                        unreadCount: _unread,
                      ),
                      const SizedBox(height: 20),
                      const Text('Notices & Announcements',
                          style: TextStyle(
                              color: AppColors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Post to $_announcementChannelName',
                          style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                      const SizedBox(height: 24),
                      _composeCard(),
                      const SizedBox(height: 28),
                      const Text('Sent Announcements',
                          style: TextStyle(
                              color: AppColors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (_sent.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text('No announcements sent yet.',
                                style: TextStyle(color: AppColors.grey)),
                          ),
                        )
                      else
                        ..._sent.map((n) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _NoticeCard(post: n),
                            )),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _composeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Compose Announcement',
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(
              hintText: 'Notice title...',
              hintStyle: const TextStyle(color: AppColors.grey),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bodyController,
            maxLines: 4,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(
              hintText: 'Write your message here...',
              hintStyle: const TextStyle(color: AppColors.grey),
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _sendNotice,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send Announcement',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellow,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final Map<String, dynamic> post;
  const _NoticeCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final content = post['content']?.toString() ?? '';
    final lines = content.split('\n');
    final title = lines.isNotEmpty ? lines.first : 'Announcement';
    final body = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';
    final author = post['author_name']?.toString() ?? 'You';
    final time = TeacherUtils.relativeTime(post['created_at']?.toString() ?? '');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_outlined, color: AppColors.yellow, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(body,
                style: const TextStyle(color: AppColors.greyLight, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 8),
          Text('$author · $time',
              style: const TextStyle(color: AppColors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}
