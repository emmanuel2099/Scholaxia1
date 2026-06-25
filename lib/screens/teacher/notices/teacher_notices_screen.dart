import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/community_badge.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/voice_note_player.dart';
import '../../../widgets/voice_note_recorder.dart';
import '../teacher_shared.dart';

class TeacherNoticesScreen extends StatefulWidget {
  const TeacherNoticesScreen({super.key});

  @override
  State<TeacherNoticesScreen> createState() => _TeacherNoticesScreenState();
}

class _TeacherNoticesScreenState extends State<TeacherNoticesScreen>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _api = ApiService();
  late TabController _tabCtrl;
  bool _sending = false;
  bool _loading = true;
  String? _teacherName;
  int _unread = 0;
  String _announcementChannelId = '';
  String _generalChannelId = '';
  String _announcementChannelName = 'Teacher Announcements';
  List<Map<String, dynamic>> _sent = [];
  List<Map<String, dynamic>> _studentPosts = [];
  List<int>? _voiceBytes;
  String? _voiceFilename;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
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
          _announcementChannelName =
              ch['name']?.toString() ?? _announcementChannelName;
        } else if (!name.contains('announcement') &&
            !name.contains('teacher') &&
            !name.contains('notice')) {
          _generalChannelId = ch['id']?.toString() ?? '';
        }
      }
      List<Map<String, dynamic>> posts = [];
      List<Map<String, dynamic>> studentPosts = [];
      if (_announcementChannelId.isNotEmpty) {
        try {
          await _api.joinChannel(channelId: _announcementChannelId);
        } catch (_) {}
        final raw = await _api.listPosts(channelId: _announcementChannelId);
        posts = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (_generalChannelId.isNotEmpty) {
        try {
          await _api.joinChannel(channelId: _generalChannelId);
        } catch (_) {}
        final raw = await _api.listPosts(channelId: _generalChannelId);
        studentPosts = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((p) => !isCommentPost(p))
            .toList();
      }
      final profile = await _api.getTeacherMe();
      final unread = await _api.unreadNotificationCount();
      if (mounted) {
        setState(() {
          _teacherName = profile['full_name']?.toString();
          _unread = unread;
          _sent = posts;
          _studentPosts = studentPosts;
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
    final hasVoice = _voiceBytes != null && _voiceFilename != null;
    if ((title.isEmpty || body.isEmpty) && !hasVoice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Fill in title and body, or record a voice note.')),
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
      String? mediaUrl;
      String? mediaType;
      if (hasVoice) {
        final res = await _api.communityUpload(_voiceBytes!, _voiceFilename!);
        mediaUrl = res['file_url'] as String?;
        mediaType = 'audio';
      }
      final content = hasVoice && title.isEmpty && body.isEmpty
          ? 'Voice announcement'
          : '$title\n\n$body';
      final post = await _api.createPost(
        channelId: _announcementChannelId,
        content: content,
        isAnonymous: false,
        visibility: 'everyone',
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      _titleController.clear();
      _bodyController.clear();
      if (mounted) {
        setState(() {
          _sent = [Map<String, dynamic>.from(post), ..._sent];
          _voiceBytes = null;
          _voiceFilename = null;
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
    final accent = context.accentColor;
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: accent))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: TeacherTopBar(
                      api: _api,
                      teacherName: _teacherName,
                      unreadCount: _unread,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text('Community',
                        style: TextStyle(
                            color: context.textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                  ),
                  TabBar(
                    controller: _tabCtrl,
                    labelColor: accent,
                    unselectedLabelColor: context.greyColor,
                    indicatorColor: accent,
                    tabs: const [
                      Tab(text: 'Announcements'),
                      Tab(text: 'Student Chat'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _announcementsTab(accent),
                        _studentChatTab(accent),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _announcementsTab(Color accent) {
    return RefreshIndicator(
      color: accent,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text('Post to $_announcementChannelName',
                style: TextStyle(color: context.greyColor, fontSize: 13)),
            const SizedBox(height: 16),
            _composeCard(),
            const SizedBox(height: 24),
            Text('Sent Announcements',
                style: TextStyle(
                    color: context.textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_sent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No announcements sent yet.',
                      style: TextStyle(color: context.greyColor)),
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
    );
  }

  Widget _studentChatTab(Color accent) {
    return RefreshIndicator(
      color: accent,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text('Student posts in General channel',
              style: TextStyle(color: context.greyColor, fontSize: 13)),
          const SizedBox(height: 16),
          if (_studentPosts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('No student posts yet.',
                    style: TextStyle(color: context.greyColor)),
              ),
            )
          else
            ..._studentPosts.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _StudentPostCard(post: p),
                )),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _composeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Compose Announcement',
              style: TextStyle(
                  color: context.textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            style: TextStyle(color: context.textColor),
            decoration: InputDecoration(
              hintText: 'Notice title...',
              hintStyle: TextStyle(color: context.greyColor),
              filled: true,
              fillColor: context.surfColor,
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
            style: TextStyle(color: context.textColor),
            decoration: InputDecoration(
              hintText: 'Write your message here...',
              hintStyle: TextStyle(color: context.greyColor),
              filled: true,
              fillColor: context.surfColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          VoiceNoteRecorder(
            onRecorded: (bytes, name) => setState(() {
              _voiceBytes = bytes;
              _voiceFilename = name;
            }),
            onCleared: () => setState(() {
              _voiceBytes = null;
              _voiceFilename = null;
            }),
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
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send Announcement',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
    final time =
        TeacherUtils.relativeTime(post['created_at']?.toString() ?? '');
    final mediaUrl = post['media_url']?.toString() ?? '';
    final mediaType = post['media_type']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined,
                  color: context.accentColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: context.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(body,
                style: TextStyle(
                    color: context.greyLColor, fontSize: 13, height: 1.4)),
          ],
          if (mediaUrl.isNotEmpty && mediaType == 'audio') ...[
            const SizedBox(height: 10),
            VoiceNotePlayer(mediaUrl: mediaUrl, label: 'Voice announcement'),
          ],
          const SizedBox(height: 8),
          Text('$author · $time',
              style: TextStyle(color: context.greyColor, fontSize: 11)),
        ],
      ),
    );
  }
}

class _StudentPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  const _StudentPostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final author = post['author_name']?.toString() ?? 'Student';
    final content = post['content']?.toString() ?? '';
    final time =
        TeacherUtils.relativeTime(post['created_at']?.toString() ?? '');
    final mediaUrl = post['media_url']?.toString() ?? '';
    final mediaType = post['media_type']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(author,
              style: TextStyle(
                  color: context.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          if (content.isNotEmpty && !content.startsWith('@post:')) ...[
            const SizedBox(height: 8),
            Text(content,
                style: TextStyle(
                    color: context.greyLColor, fontSize: 13, height: 1.4)),
          ],
          if (mediaUrl.isNotEmpty && mediaType == 'audio') ...[
            const SizedBox(height: 10),
            VoiceNotePlayer(mediaUrl: mediaUrl),
          ],
          const SizedBox(height: 8),
          Text(time, style: TextStyle(color: context.greyColor, fontSize: 11)),
        ],
      ),
    );
  }
}
