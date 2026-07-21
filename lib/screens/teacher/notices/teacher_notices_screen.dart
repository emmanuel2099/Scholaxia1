import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../api/api_service.dart';
import '../../../services/community_badge.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/voice_note_player.dart';
import '../../../widgets/voice_note_recorder.dart';
import '../../student/community/post_comments_sheet.dart';
import '../teacher_shared.dart';

class TeacherNoticesScreen extends StatefulWidget {
  const TeacherNoticesScreen({super.key});

  @override
  State<TeacherNoticesScreen> createState() => _TeacherNoticesScreenState();
}

class _TeacherNoticesScreenState extends State<TeacherNoticesScreen>
    with SingleTickerProviderStateMixin {
  final _bodyController = TextEditingController();
  final _api = ApiService();
  late TabController _tabCtrl;
  bool _sending = false;
  bool _recordingVoice = false;
  bool _loading = true;
  String? _teacherName;
  int _unread = 0;
  String _announcementChannelId = '';
  String _generalChannelId = '';
  String _announcementChannelName = 'Teacher Announcements';
  List<Map<String, dynamic>> _sent = [];
  List<Map<String, dynamic>> _studentPosts = [];
  Map<String, List<Map<String, dynamic>>> _comments = {};
  Map<String, dynamic>? _replyingTo;
  List<int>? _voiceBytes;
  String? _voiceFilename;
  List<int>? _pdfBytes;
  String? _pdfFilename;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
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
      final comments = <String, List<Map<String, dynamic>>>{};
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
        try {
          final rawC =
              await _api.listAllPostComments(channelId: _generalChannelId);
          for (final c in rawC.whereType<Map>()) {
            final m = Map<String, dynamic>.from(c);
            final pid = _commentPostId(m['content']?.toString() ?? '');
            if (pid == null) continue;
            comments.putIfAbsent(pid, () => []).add(m);
          }
        } catch (_) {}
      }
      final profile = await _api.getTeacherMe();
      final unread = await _api.unreadNotificationCount();
      if (mounted) {
        setState(() {
          _teacherName = profile['full_name']?.toString();
          _unread = unread;
          _sent = posts;
          _studentPosts = studentPosts;
          _comments = comments;
          _loading = false;
        });
        teacherUnreadCount.value = unread;
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendNotice() async {
    final text = _bodyController.text.trim();
    final hasVoice = _voiceBytes != null && _voiceFilename != null;
    final hasPdf = _pdfBytes != null && _pdfFilename != null;
    String title;
    String body;
    if (text.contains('\n')) {
      final i = text.indexOf('\n');
      title = text.substring(0, i).trim();
      body = text.substring(i + 1).trim();
    } else {
      title = text;
      body = text;
    }
    if (text.isEmpty && !hasVoice && !hasPdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Write a message, attach a PDF, or record a voice note.')),
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
      if (hasPdf) {
        final res = await _api.communityUpload(_pdfBytes!, _pdfFilename!);
        mediaUrl = res['file_url'] as String?;
        mediaType = 'pdf';
      } else if (hasVoice) {
        final res = await _api.communityUpload(_voiceBytes!, _voiceFilename!);
        mediaUrl = res['file_url'] as String?;
        mediaType = 'audio';
      }
      final content = text.isEmpty
          ? (hasPdf ? 'PDF assignment' : 'Voice announcement')
          : '$title\n\n$body';
      final post = await _api.createPost(
        channelId: _announcementChannelId,
        content: content,
        isAnonymous: false,
        visibility: 'everyone',
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      _bodyController.clear();
      if (mounted) {
        setState(() {
          _sent = [Map<String, dynamic>.from(post), ..._sent];
          _voiceBytes = null;
          _voiceFilename = null;
          _pdfBytes = null;
          _pdfFilename = null;
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

  Future<void> _pickAssignmentPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null) return;
    setState(() {
      _pdfBytes = file.bytes;
      _pdfFilename = file.name;
      _voiceBytes = null;
      _voiceFilename = null;
    });
  }

  static String? _commentPostId(String content) {
    final m = RegExp(r'^@post:(\S+)').firstMatch(content);
    return m?.group(1);
  }

  Future<void> _sendStudentChat() async {
    final text = _bodyController.text.trim();
    final hasVoice = _voiceBytes != null && _voiceFilename != null;
    if (text.isEmpty && !hasVoice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a message or record a voice note.')),
      );
      return;
    }
    if (_generalChannelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student chat channel not found.')),
      );
      return;
    }
    final replyTo = _replyingTo;
    setState(() => _sending = true);
    try {
      // Voice notes aren't supported on threaded replies, so send a normal
      // reply for text and fall back to a post for voice.
      if (replyTo != null && !hasVoice) {
        final postId = replyTo['id']?.toString() ?? '';
        final comment = await _api.addPostComment(
          postId: postId,
          channelId: _generalChannelId,
          content: text,
        );
        _bodyController.clear();
        if (mounted) {
          setState(() {
            _comments.putIfAbsent(postId, () => []).add(
                  Map<String, dynamic>.from(comment),
                );
            _replyingTo = null;
          });
        }
        return;
      }

      String? mediaUrl;
      String? mediaType;
      if (hasVoice) {
        final res = await _api.communityUpload(_voiceBytes!, _voiceFilename!);
        mediaUrl = res['file_url'] as String?;
        mediaType = 'audio';
      }
      final content = hasVoice && text.isEmpty ? 'Voice message' : text;
      final post = await _api.createPost(
        channelId: _generalChannelId,
        content: content,
        isAnonymous: false,
        visibility: 'everyone',
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      _bodyController.clear();
      if (mounted) {
        setState(() {
          _studentPosts = [Map<String, dynamic>.from(post), ..._studentPosts];
          _voiceBytes = null;
          _voiceFilename = null;
          _replyingTo = null;
        });
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
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: accent))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TeacherTopBar(
                      api: _api,
                      teacherName: _teacherName,
                      unreadCount: _unread,
                    ),
                  ),
                  TeacherHeroHeader(
                    greeting: 'Community',
                    subtitle:
                        'Post announcements and monitor student conversations.',
                    icon: Icons.people_rounded,
                    badge: _studentPosts.isNotEmpty
                        ? '${_studentPosts.length} POSTS'
                        : null,
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
                        _announcementsList(accent),
                        _studentChatTab(accent),
                      ],
                    ),
                  ),
                  _composeBar(accent, chat: _tabCtrl.index == 1),
                ],
              ),
      ),
    );
  }

  Widget _announcementsList(Color accent) {
    return RefreshIndicator(
      color: accent,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        children: [
          Text('Sent Announcements',
              style: TextStyle(
                  color: context.textColor,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_sent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.campaign_outlined,
                        color: context.greyColor, size: 44),
                    const SizedBox(height: 12),
                    Text('No announcements sent yet.',
                        style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Type below — first line is the title.',
                        style: TextStyle(
                            color: context.greyColor, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            ..._sent.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _NoticeCard(post: n),
                )),
        ],
      ),
    );
  }

  Widget _studentChatTab(Color accent) {
    return RefreshIndicator(
      color: accent,
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        itemCount: _studentPosts.isEmpty ? 1 : _studentPosts.length,
        itemBuilder: (context, i) {
          if (_studentPosts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        color: context.greyColor, size: 44),
                    const SizedBox(height: 12),
                    Text('No student posts yet',
                        style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            );
          }
          final p = _studentPosts[i];
          final author = p['author_name']?.toString() ?? '';
          final isOwn = _teacherName != null &&
              author.isNotEmpty &&
              author == _teacherName;
          final pid = p['id']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _StudentPostCard(
              post: p,
              isOwn: isOwn,
              commentCount: (_comments[pid] ?? const []).length,
              onOpenComments: () => _openComments(p),
              onEdit: isOwn ? () => _editTeacherPost(p) : null,
              onDelete: isOwn ? () => _deleteTeacherPost(pid) : null,
            ),
          );
        },
      ),
    );
  }

  void _openComments(Map<String, dynamic> post) {
    final postId = post['id']?.toString() ?? '';
    if (postId.isEmpty || _generalChannelId.isEmpty) return;
    final author = post['author_name']?.toString() ?? 'Student';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PostCommentsSheet(
        postId: postId,
        channelId: _generalChannelId,
        postAuthor: author,
        onCountChanged: (count) {
          if (!mounted) return;
          setState(() {
            // Keep local cache length in sync after sheet edits.
            final list = _comments.putIfAbsent(postId, () => []);
            while (list.length > count) {
              list.removeLast();
            }
          });
        },
      ),
    ).then((_) => _load());
  }

  Future<void> _editTeacherPost(Map<String, dynamic> post) async {
    final postId = post['id']?.toString() ?? '';
    if (postId.isEmpty) return;
    final ctrl = TextEditingController(text: post['content']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: ctrl, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      await _api.updateCommunityPost(postId: postId, content: text);
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _studentPosts.length; i++) {
          if (_studentPosts[i]['id']?.toString() == postId) {
            _studentPosts[i] = {..._studentPosts[i], 'content': text};
          }
        }
        for (var i = 0; i < _sent.length; i++) {
          if (_sent[i]['id']?.toString() == postId) {
            _sent[i] = {..._sent[i], 'content': text};
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Edit failed')),
        );
      }
    }
  }

  Future<void> _deleteTeacherPost(String postId) async {
    if (postId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteCommunityPost(postId);
      if (!mounted) return;
      setState(() {
        _studentPosts.removeWhere((p) => p['id']?.toString() == postId);
        _sent.removeWhere((p) => p['id']?.toString() == postId);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Delete failed')),
        );
      }
    }
  }

  Widget _composeBar(Color accent, {bool chat = false}) {
    final hasVoice = _voiceBytes != null;
    final hasPdf = _pdfBytes != null;
    final hasText = _bodyController.text.trim().isNotEmpty;
    final canSend = !_sending && (hasText || hasVoice || (!chat && hasPdf));
    final sendFg = context.isDark ? AppColors.background : Colors.white;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final navPad = bottomInset > 0 ? 12.0 : 88.0;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, navPad),
      decoration: BoxDecoration(
        color: context.headerColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chat && _replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, color: accent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to ${_replyingTo!['author_name'] ?? 'student'}',
                      style: TextStyle(color: accent, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = null),
                    child: Icon(Icons.close, color: context.greyColor, size: 18),
                  ),
                ],
              ),
            ),
          if (_recordingVoice)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Recording… tap stop when done',
                  style: TextStyle(color: Colors.red.shade400, fontSize: 12)),
            ),
          if (hasVoice && !_recordingVoice)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.mic_rounded, color: accent, size: 16),
                const SizedBox(width: 6),
                Text('Voice note ready',
                    style: TextStyle(color: context.greyColor, fontSize: 12)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    _voiceBytes = null;
                    _voiceFilename = null;
                  }),
                  child: Icon(Icons.close, color: context.greyColor, size: 18),
                ),
              ]),
            ),
          if (!chat && hasPdf)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_rounded,
                      color: Colors.red, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _pdfFilename ?? 'Assignment PDF',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.greyColor, fontSize: 12),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _pdfBytes = null;
                      _pdfFilename = null;
                    }),
                    child: Icon(Icons.close, color: context.greyColor, size: 18),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(chat ? Icons.chat_bubble_outline : Icons.campaign_outlined,
                  color: accent, size: 22),
              if (!chat)
                IconButton(
                  tooltip: 'Attach assignment PDF',
                  onPressed: _sending ? null : _pickAssignmentPdf,
                  icon: const Icon(Icons.attach_file_rounded),
                  color: accent,
                ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _bodyController,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(color: context.textColor, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: chat
                        ? 'Message students…'
                        : 'Title on first line, then message…',
                    hintStyle:
                        TextStyle(color: context.greyColor, fontSize: 14),
                    filled: true,
                    fillColor: context.surfColor,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: accent, width: 1.5),
                    ),
                    suffixIcon: InlineVoiceMicButton(
                      hasRecording: hasVoice,
                      onRecordingChanged: (v) =>
                          setState(() => _recordingVoice = v),
                      onRecorded: (bytes, name) => setState(() {
                        _voiceBytes = bytes;
                        _voiceFilename = name;
                      }),
                      onCleared: () => setState(() {
                        _voiceBytes = null;
                        _voiceFilename = null;
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: canSend ? accent : context.surfColor,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  onTap: canSend
                      ? (chat ? _sendStudentChat : _sendNotice)
                      : null,
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: _sending
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: sendFg,
                            ),
                          )
                        : Icon(Icons.send_rounded,
                            color: canSend ? sendFg : context.greyColor,
                            size: 22),
                  ),
                ),
              ),
            ],
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
  final bool isOwn;
  final int commentCount;
  final VoidCallback? onOpenComments;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _StudentPostCard({
    required this.post,
    this.isOwn = false,
    this.commentCount = 0,
    this.onOpenComments,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final author =
        isOwn ? 'You' : (post['author_name']?.toString() ?? 'Student');
    final content = post['content']?.toString() ?? '';
    final time =
        TeacherUtils.relativeTime(post['created_at']?.toString() ?? '');
    final mediaUrl = post['media_url']?.toString() ?? '';
    final mediaType = post['media_type']?.toString() ?? '';
    final text = content.startsWith('@post:') ? '' : content;
    final nameColor = isOwn ? context.accentColor : context.textColor;

    // Feed shows the message only. Tap Comment to open replies (Facebook-style).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: context.accentColor.withOpacity(0.22),
          child: Text(
            author.isNotEmpty ? author[0].toUpperCase() : 'S',
            style: TextStyle(
              color: context.accentColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: onOpenComments,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.surfColor,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              author,
                              style: TextStyle(
                                color: nameColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (text.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                text,
                                style: TextStyle(
                                  color: context.textColor,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isOwn && (onEdit != null || onDelete != null))
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: Icon(Icons.more_horiz,
                          size: 18, color: context.greyColor),
                      onSelected: (v) {
                        if (v == 'edit') onEdit?.call();
                        if (v == 'delete') onDelete?.call();
                      },
                      itemBuilder: (_) => [
                        if (onEdit != null)
                          const PopupMenuItem(
                              value: 'edit', child: Text('Edit')),
                        if (onDelete != null)
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                      ],
                    ),
                ],
              ),
              if (mediaUrl.isNotEmpty && mediaType == 'audio') ...[
                const SizedBox(height: 6),
                VoiceNotePlayer(mediaUrl: mediaUrl),
              ],
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  children: [
                    GestureDetector(
                      onTap: onOpenComments,
                      child: Text(
                        commentCount > 0
                            ? (commentCount == 1
                                ? '1 comment'
                                : '$commentCount comments')
                            : 'Comment',
                        style: TextStyle(
                          color: commentCount > 0
                              ? context.accentColor
                              : context.greyLColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style:
                          TextStyle(color: context.greyColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
