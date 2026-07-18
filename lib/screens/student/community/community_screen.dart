import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/community_badge.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import '../../../widgets/app_header_actions.dart';
import '../../../widgets/author_avatar.dart';
import '../../../widgets/voice_note_player.dart';
import '../../../widgets/voice_note_recorder.dart';
import 'new_post_screen.dart';
import 'join_channel_screen.dart';
import 'post_comments_sheet.dart';
import '../groups/groups_panel.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _api = ApiService();
  final _messageCtrl = TextEditingController();
  final _feedScroll = ScrollController();
  List<dynamic> _channels = [];
  List<dynamic> _posts = [];
  List<dynamic> _pinnedPosts = [];
  List<dynamic> _announcementPosts = [];
  bool _loadingChannels = true;
  bool _loadingPosts = false;
  bool _loadingAnnouncements = false;
  bool _sendingMessage = false;
  bool _recordingVoice = false;
  List<int>? _voiceBytes;
  String? _voiceFilename;
  int _tabIndex = 0;
  String _generalChannelId = '';

  String _generalChannelName = '';
  final Map<String, int> _commentCounts = {};
  /// Replies keyed by parent post id — shown inline (no need to open sheet).
  final Map<String, List<Map<String, dynamic>>> _commentsByPost = {};
  String? _myUserId;
  String? _channelError;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging && _tabCtrl.index != _tabIndex) {
        setState(() => _tabIndex = _tabCtrl.index);
        if (_tabCtrl.index == 2) {
          _loadAnnouncements();
          clearCommunityBadge(_api);
        }
      }
    });
    _api.getUserId().then((id) {
      if (mounted) setState(() => _myUserId = id);
    });
    _loadChannels();
    refreshCommunityBadge(_api);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _messageCtrl.dispose();
    _feedScroll.dispose();
    super.dispose();
  }

  void _scrollFeedToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_feedScroll.hasClients) return;
      final target = _feedScroll.position.maxScrollExtent;
      if (animated) {
        _feedScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        _feedScroll.jumpTo(target);
      }
    });
  }

  List<Map<String, dynamic>> _chronologicalPosts() {
    final list = _posts
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    list.sort((a, b) {
      final at = a['created_at']?.toString() ?? '';
      final bt = b['created_at']?.toString() ?? '';
      return at.compareTo(bt);
    });
    return list;
  }

  Future<void> _loadChannels() async {
    setState(() {
      _loadingChannels = true;
      _channelError = null;
    });
    try {
      final data = await _api.communityChannels();
      if (!mounted) return;
      if (data.isEmpty) {
        setState(() {
          _channels = [];
          _loadingChannels = false;
          _channelError =
              'No community channels yet. Ask admin to create the General channel.';
        });
        return;
      }
      setState(() {
        _channels = data;
        _loadingChannels = false;
      });
      final general = data.firstWhere(
        (c) {
          final m = Map<String, dynamic>.from(c as Map);
          final n = m['name']?.toString().toLowerCase() ?? '';
          final t = m['type']?.toString().toLowerCase() ??
              m['channel_type']?.toString().toLowerCase() ??
              '';
          if (t.contains('announce') || t.contains('teacher')) return false;
          return !n.contains('teacher') &&
              !n.contains('announcement') &&
              !n.contains('notice');
        },
        orElse: () => data.first,
      );
      final g = Map<String, dynamic>.from(general as Map);
      _generalChannelId = g['id']?.toString() ?? '';
      _generalChannelName = g['name']?.toString() ?? 'General';
      if (_generalChannelId.isEmpty) {
        setState(() {
          _channelError = 'Community channel is missing. Pull to refresh.';
        });
        return;
      }
      try {
        await _api.joinChannel(channelId: _generalChannelId);
      } catch (_) {}
      await Future.wait([
        _loadPosts(keepExistingOnError: false),
        _loadPinnedPosts(),
        _loadAnnouncements(),
      ]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingChannels = false;
          _channelError =
              'Could not connect to Community. Check your internet and tap Retry.';
        });
      }
    }
  }

  Future<void> _loadPosts({bool keepExistingOnError = true}) async {
    if (_generalChannelId.isEmpty) return;
    setState(() => _loadingPosts = true);
    try {
      List<dynamic> postsRaw = const [];
      List<dynamic> msgsRaw = const [];
      try {
        postsRaw = await _api.listPosts(channelId: _generalChannelId, limit: 80);
      } catch (_) {}
      try {
        msgsRaw = await _api.getMessages(channelId: _generalChannelId, limit: 80);
      } catch (_) {}

      final posts = postsRaw.where((p) {
        if (p is! Map) return false;
        return !isCommentPost(Map<String, dynamic>.from(p));
      }).map((p) => Map<String, dynamic>.from(p as Map)).toList();

      // Merge legacy chat messages so older/desktop chat still appears.
      for (final raw in msgsRaw) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (posts.any((p) => p['id']?.toString() == id)) continue;
        posts.add({
          'id': id,
          'content': m['content'] ?? m['text'] ?? '',
          'created_at': m['created_at'],
          'author_name': m['sender_name'] ?? m['author_name'] ?? 'Student',
          'author_id': m['sender_id'] ?? m['user_id'],
          'author_picture': m['author_picture'] ?? m['profile_picture'],
          'profile_picture': m['profile_picture'] ?? m['author_picture'],
          'media_url': m['media_url'],
          'media_type': m['media_type'],
          'is_message': true,
        });
      }

      posts.sort((a, b) {
        final at = a['created_at']?.toString() ?? '';
        final bt = b['created_at']?.toString() ?? '';
        return at.compareTo(bt);
      });

      if (mounted) {
        setState(() {
          _posts = posts;
          _loadingPosts = false;
          if (postsRaw.isEmpty && msgsRaw.isEmpty) {
            // keep empty state but clear network error if request succeeded
            _channelError = null;
          } else {
            _channelError = null;
          }
        });
        _scrollFeedToBottom(animated: false);
      }
      await _loadCommentCounts();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!keepExistingOnError) _posts = [];
          _loadingPosts = false;
          _channelError =
              'Could not load messages. Check your internet and tap Refresh.';
        });
      }
    }
  }

  void _appendPost(Map<String, dynamic> post) {
    final id = post['id']?.toString() ?? '';
    final enriched = Map<String, dynamic>.from(post);
    // Ensure my avatar shows immediately after posting.
    final isMine = _myUserId != null &&
        (enriched['author_id']?.toString() == _myUserId ||
            enriched['author_name']?.toString().toLowerCase() == 'you');
    if (isMine &&
        (enriched['author_picture'] == null ||
            enriched['author_picture'].toString().isEmpty)) {
      // Will prefer local cache via AuthorAvatar(preferLocalCache: true)
      enriched['_mine'] = true;
    }
    setState(() {
      final kept = _posts
          .where((p) => (p as Map<String, dynamic>)['id']?.toString() != id)
          .toList();
      _posts = [...kept, enriched];
      _posts.sort((a, b) {
        final at = (a as Map<String, dynamic>)['created_at']?.toString() ?? '';
        final bt = (b as Map<String, dynamic>)['created_at']?.toString() ?? '';
        return at.compareTo(bt);
      });
    });
    _scrollFeedToBottom();
  }

  Future<void> _sendQuickMessage() async {
    final text = _messageCtrl.text.trim();
    if ((text.isEmpty && _voiceBytes == null) || _sendingMessage) {
      return;
    }
    if (_generalChannelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Community not connected yet. Tap Retry / Refresh and check internet.'),
          backgroundColor: Colors.red,
        ),
      );
      await _loadChannels();
      return;
    }

    setState(() => _sendingMessage = true);
    try {
      try {
        await _api.joinChannel(channelId: _generalChannelId);
      } catch (_) {}

      String? mediaUrl;
      String? mediaType;
      if (_voiceBytes != null && _voiceFilename != null) {
        final upload =
            await _api.communityUpload(_voiceBytes!, _voiceFilename!);
        mediaUrl = upload['file_url'] as String?;
        mediaType = 'audio';
      }

      Map<String, dynamic>? post;
      try {
        post = await _api.createPost(
          channelId: _generalChannelId,
          content: text.isEmpty ? 'Voice note' : text,
          mediaUrl: mediaUrl,
          mediaType: mediaType,
        );
      } on ApiException catch (e) {
        final msg = e.message.toLowerCase();
        if (msg.contains('join') || msg.contains('member')) {
          rethrow;
        }
        // Fall back to legacy messages API so chat still works.
        final msgMap = await _api.sendMessage(
          channelId: _generalChannelId,
          content: text.isEmpty ? 'Voice note' : text,
          mediaUrl: mediaUrl,
          mediaType: mediaType,
        );
        post = {
          'id': msgMap['id'],
          'content': msgMap['content'] ?? text,
          'created_at': msgMap['created_at'],
          'author_name': msgMap['sender_name'] ?? 'You',
          'author_id': msgMap['sender_id'],
          'author_picture': msgMap['author_picture'] ?? msgMap['profile_picture'],
          'profile_picture': msgMap['profile_picture'] ?? msgMap['author_picture'],
          'media_url': mediaUrl,
          'media_type': mediaType,
          'is_message': true,
          '_mine': true,
        };
      }
      if (!mounted) return;
      _messageCtrl.clear();
      setState(() {
        _voiceBytes = null;
        _voiceFilename = null;
      });
      if (post != null) {
        final pic = await _api.cachedProfilePicture();
        if (pic != null && pic.isNotEmpty) {
          post = {
            ...post,
            'author_picture': post['author_picture'] ?? pic,
            'profile_picture': post['profile_picture'] ?? pic,
            '_mine': true,
          };
        } else {
          post = {...post, '_mine': true};
        }
        _appendPost(post);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('join') || msg.contains('member')) {
        final joined = await Navigator.push(context, MaterialPageRoute(
          builder: (_) => JoinChannelScreen(
            channelId: _generalChannelId,
            channelName:
                _generalChannelName.isNotEmpty ? _generalChannelName : 'General',
          ),
        ));
        if (joined == true && mounted) {
          try {
            final post = await _api.createPost(
              channelId: _generalChannelId,
              content: text.isEmpty ? 'Voice note' : text,
            );
            _messageCtrl.clear();
            _appendPost(post);
          } on ApiException catch (e2) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e2.message), backgroundColor: Colors.red),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Could not send. Check internet and try again. (${e.toString()})'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  Future<void> _handleNewPostResult(dynamic result) async {
    if (result is Map<String, dynamic>) {
      _appendPost(result);
      return;
    }
    if (result == 'join_required') {
      final joined = await Navigator.push(context, MaterialPageRoute(
        builder: (_) => JoinChannelScreen(
          channelId: _generalChannelId,
          channelName: _generalChannelName.isNotEmpty ? _generalChannelName : 'General',
        ),
      ));
      if (joined == true) await _loadPosts(keepExistingOnError: true);
      return;
    }
    if (result == true) {
      await _loadPosts(keepExistingOnError: true);
    }
  }

  Future<void> _loadPinnedPosts() async {
    if (_generalChannelId.isEmpty) return;
    try {
      final data = await _api.getPinnedPosts(_generalChannelId);
      if (mounted) setState(() { _pinnedPosts = data; });
    } catch (_) {
      // Silently ignore pinned posts errors
      if (mounted) setState(() { _pinnedPosts = []; });
    }
  }

  Future<void> _loadCommentCounts() async {
    if (_generalChannelId.isEmpty) return;
    try {
      final comments = await _api.listAllPostComments(channelId: _generalChannelId);
      final counts = <String, int>{};
      final byPost = <String, List<Map<String, dynamic>>>{};
      for (final m in comments) {
        if (m is! Map) continue;
        final map = Map<String, dynamic>.from(m);
        final content = map['content']?.toString() ?? '';
        final match = RegExp(r'^@post:([^\s]+)').firstMatch(content);
        if (match != null) {
          final id = match.group(1)!;
          counts[id] = (counts[id] ?? 0) + 1;
          byPost.putIfAbsent(id, () => []).add(map);
        }
      }
      for (final list in byPost.values) {
        list.sort((a, b) => (a['created_at']?.toString() ?? '')
            .compareTo(b['created_at']?.toString() ?? ''));
      }
      if (mounted) setState(() {
        _commentCounts
          ..clear()
          ..addAll(counts);
        _commentsByPost
          ..clear()
          ..addAll(byPost);
      });
    } catch (_) {}
  }

  Future<void> _loadAnnouncements() async {
    if (_announcementChannels.isEmpty) return;
    setState(() => _loadingAnnouncements = true);
    final all = <Map<String, dynamic>>[];
    try {
      for (final ch in _announcementChannels) {
        final channel = ch as Map<String, dynamic>;
        final channelId = channel['id']?.toString() ?? '';
        final channelName = channel['name']?.toString() ?? 'Announcements';
        if (channelId.isEmpty) continue;
        try {
          await _api.joinChannel(channelId: channelId);
        } catch (_) {}
        try {
          final posts = await _api.listPosts(channelId: channelId);
          for (final p in posts) {
            if (p is Map) {
              all.add({
                ...Map<String, dynamic>.from(p),
                'channel_name': channelName,
              });
            }
          }
        } catch (_) {
          try {
            final msgs = await _api.getMessages(channelId: channelId);
            for (final m in msgs) {
              if (m is Map) {
                all.add({
                  'id': m['id']?.toString() ?? '',
                  'content': m['content']?.toString() ?? '',
                  'author_name': m['author_name']?.toString() ?? 'Teacher',
                  'created_at': m['created_at']?.toString() ?? '',
                  'channel_name': channelName,
                });
              }
            }
          } catch (_) {}
        }
      }
      all.sort((a, b) {
        final at = a['created_at']?.toString() ?? '';
        final bt = b['created_at']?.toString() ?? '';
        return bt.compareTo(at);
      });
    } finally {
      if (mounted) {
        setState(() {
          _announcementPosts = all;
          _loadingAnnouncements = false;
        });
      }
    }
  }

  Future<void> _openNewPost() async {
    final result = await Navigator.push(context, MaterialPageRoute(
      builder: (_) => NewPostScreen(
        channels: _generalChannelId.isNotEmpty ? [_generalChannelName] : [],
        channelIdMap: {_generalChannelName: _generalChannelId},
      ),
    ));
    if (!mounted) return;
    await _handleNewPostResult(result);
  }

  void _updatePost(String postId, Map<String, dynamic> updates) {
    void patch(List<dynamic> list) {
      for (var i = 0; i < list.length; i++) {
        final p = list[i] as Map<String, dynamic>;
        if (p['id']?.toString() == postId) {
          list[i] = {...p, ...updates};
        }
      }
    }

    setState(() {
      patch(_posts);
      patch(_pinnedPosts);
    });
  }

  Future<void> _toggleLike(String postId) async {
    Map<String, dynamic>? post;
    for (final p in [..._posts, ..._pinnedPosts]) {
      if ((p as Map<String, dynamic>)['id']?.toString() == postId) {
        post = Map<String, dynamic>.from(p);
        break;
      }
    }
    if (post == null) return;

    final liked = post['liked_by_me'] as bool? ?? false;
    final count = post['like_count'] as int? ?? 0;
    _updatePost(postId, {
      'liked_by_me': !liked,
      'like_count': liked ? (count > 0 ? count - 1 : 0) : count + 1,
    });

    try {
      final res = await _api.toggleLike(postId);
      final updates = <String, dynamic>{};
      if (res['like_count'] != null) updates['like_count'] = res['like_count'];
      if (res['liked_by_me'] != null) {
        updates['liked_by_me'] = res['liked_by_me'];
      } else if (res['liked'] != null) {
        updates['liked_by_me'] = res['liked'];
      }
      if (updates.isNotEmpty) _updatePost(postId, updates);
    } catch (_) {
      _updatePost(postId, {'liked_by_me': liked, 'like_count': count});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update like. Try again.')),
        );
      }
    }
  }

  void _openComments(BuildContext context, Map<String, dynamic> post) {
    final postId = post['id']?.toString() ?? '';
    if (postId.isEmpty || _generalChannelId.isEmpty) return;
    final isAnonymous = post['is_anonymous'] as bool? ?? false;
    final author = isAnonymous
        ? 'Anonymous'
        : (post['author_name'] as String? ?? 'Student');

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
          if (mounted) setState(() => _commentCounts[postId] = count);
        },
      ),
    ).then((_) => _loadCommentCounts());
  }

  List<dynamic> get _announcementChannels => _channels.where((c) {
    final n = (c as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
    return n.contains('teacher') || n.contains('announcement') || n.contains('notice');
  }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _buildHeader(context),
          _buildTabBar(context),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildGeneralTab(context),
                const GroupsPanel(),
                _buildAnnouncementsTab(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: context.headerColor,
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
      child: Row(children: [
        const StudentBackButton(),
        Container(width: 32, height: 32,
          decoration: BoxDecoration(color: context.accentColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.school_outlined, color: context.accentColor, size: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Scholaxia',
              style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const AppHeaderActions(),
      ]),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      color: context.headerColor,
      child: TabBar(
        controller: _tabCtrl,
        labelColor: context.accentColor,
        unselectedLabelColor: context.greyColor,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        indicatorColor: context.accentColor,
        indicatorWeight: 2,
        tabs: const [
          Tab(text: 'General'),
          Tab(text: 'Groups'),
          Tab(text: 'Announcements'),
        ],
      ),
    );
  }

  Widget _buildGeneralTab(BuildContext context) {
    if (_loadingChannels) {
      return Center(child: CircularProgressIndicator(color: context.accentColor));
    }
    if (_generalChannelId.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, color: context.greyColor, size: 48),
              const SizedBox(height: 12),
              Text(
                _channelError ??
                    'Could not open Community. Check your internet connection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textColor, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadChannels,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor:
                      context.isDark ? AppColors.background : Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: context.accentColor,
            onRefresh: () async {
              await _loadChannels();
            },
            child: ListView(
              controller: _feedScroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                if (_channelError != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.35)),
                    ),
                    child: Text(_channelError!,
                        style: TextStyle(color: context.textColor, fontSize: 12)),
                  ),
                ],
                if (_pinnedPosts.isNotEmpty) ...[
                  Text('Pinned Posts',
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._pinnedPosts.map((p) {
                    final post = p as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildPostFromApi(context, post, isPinned: true),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Messages',
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  TextButton(
                      onPressed: () => _loadPosts(keepExistingOnError: true),
                      child: Text('Refresh',
                          style: TextStyle(color: context.accentColor, fontSize: 12))),
                ]),
                const SizedBox(height: 8),
                if (_loadingPosts)
                  Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: context.accentColor)))
                else if (_posts.isEmpty)
                  _buildEmptyFeed(context)
                else
                  ..._chronologicalPosts().map((post) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildPostFromApi(context, post),
                    );
                  }),
              ],
            ),
          ),
        ),
        _buildMessageComposer(context),
      ],
    );
  }

  Widget _buildMessageComposer(BuildContext context) {
    final hasText = _messageCtrl.text.trim().isNotEmpty;
    final hasVoice = _voiceBytes != null;
    final canSend = !_sendingMessage && (hasText || hasVoice);
    final sendFg = context.isDark ? AppColors.background : Colors.white;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      decoration: BoxDecoration(
        color: context.headerColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                Icon(Icons.mic_rounded, color: context.accentColor, size: 16),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: _generalChannelId.isEmpty ? null : _openNewPost,
                tooltip: 'Photo post',
                icon: Icon(Icons.add_circle_outline_rounded,
                    color: context.accentColor),
              ),
              Expanded(
                child: TextField(
                  controller: _messageCtrl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _sendQuickMessage(),
                  style: TextStyle(color: context.textColor, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: _generalChannelId.isEmpty
                        ? 'Loading community…'
                        : 'Write a message…',
                    hintStyle: TextStyle(color: context.greyColor, fontSize: 14),
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
                      borderSide:
                          BorderSide(color: context.accentColor, width: 1.5),
                    ),
                    suffixIcon: InlineVoiceMicButton(
                      hasRecording: hasVoice,
                      onRecordingChanged: (v) =>
                          setState(() => _recordingVoice = v),
                      onRecorded: (bytes, name) => setState(() {
                        _voiceBytes = bytes;
                        _voiceFilename = name;
                        _recordingVoice = false;
                      }),
                      onCleared: () => setState(() {
                        _voiceBytes = null;
                        _voiceFilename = null;
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: canSend
                    ? context.accentColor
                    : context.greyColor.withOpacity(0.35),
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  onTap: canSend ? _sendQuickMessage : null,
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: _sendingMessage
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: sendFg,
                            ),
                          )
                        : Icon(Icons.send_rounded, color: sendFg, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFeed(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(child: Column(children: [
        Icon(Icons.forum_outlined, color: context.greyColor, size: 48),
        const SizedBox(height: 12),
        Text('No posts yet', style: TextStyle(color: context.textColor, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Type a message below to start the conversation!',
            style: TextStyle(color: context.greyColor, fontSize: 13)),
      ])),
    );
  }

  bool _canEditPost(Map<String, dynamic> post) {
    final authorId = post['author_id']?.toString() ?? '';
    if (_myUserId == null || _myUserId!.isEmpty || authorId.isEmpty) return false;
    return authorId.toLowerCase() == _myUserId!.toLowerCase();
  }

  Future<void> _editPost(Map<String, dynamic> post) async {
    final postId = post['id']?.toString() ?? '';
    if (postId.isEmpty) return;
    final ctrl = TextEditingController(text: post['content']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Update your message'),
        ),
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
        for (final list in [_posts, _pinnedPosts, _announcementPosts]) {
          for (var i = 0; i < list.length; i++) {
            if (list[i] is Map && list[i]['id']?.toString() == postId) {
              list[i] = {...Map<String, dynamic>.from(list[i] as Map), 'content': text};
            }
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Could not edit')),
        );
      }
    }
  }

  Future<void> _confirmDeletePost(String postId) async {
    if (postId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This removes the message for everyone.'),
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
        _posts.removeWhere((p) => p is Map && p['id']?.toString() == postId);
        _pinnedPosts.removeWhere((p) => p is Map && p['id']?.toString() == postId);
        _announcementPosts.removeWhere((p) => p is Map && p['id']?.toString() == postId);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Could not delete')),
        );
      }
    }
  }

  Widget _buildPostFromApi(BuildContext context, Map<String, dynamic> post, {bool isPinned = false}) {
    final isAnonymous = post['is_anonymous'] as bool? ?? false;
    final authorName = isAnonymous
        ? 'Anonymous'
        : (post['author_name'] as String? ??
            post['author'] as String? ??
            'Student');
    final content = post['content'] as String? ?? '';
    final createdAt = post['created_at'] as String? ?? '';
    final likeCount = post['like_count'] as int? ?? 0;
    final likedByMe = post['liked_by_me'] as bool? ?? false;
    final postId = post['id'] as String? ?? '';
    final commentCount = _commentCounts[postId] ?? post['comment_count'] as int? ?? 0;
    final mediaUrl = post['media_url']?.toString() ?? '';
    final mediaType = post['media_type']?.toString() ?? '';
    final picture = post['author_picture']?.toString() ??
        post['profile_picture']?.toString();
    final isMine = post['_mine'] == true ||
        _canEditPost(post) ||
        (_myUserId != null &&
            post['author_id']?.toString() == _myUserId);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isPinned ? context.accentColor : context.borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AuthorAvatar(
            pictureUrl: picture,
            name: authorName,
            radius: 20,
            preferLocalCache: isMine && !isAnonymous,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(authorName, style: TextStyle(color: context.textColor, fontSize: 13, fontWeight: FontWeight.w600)),
              if (isPinned) ...[
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: context.accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('Pinned', style: TextStyle(color: context.accentColor, fontSize: 10, fontWeight: FontWeight.w600))),
              ],
            ]),
            Text(_formatTime(createdAt), style: TextStyle(color: context.greyColor, fontSize: 11)),
          ])),
          if (_canEditPost(post))
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: context.greyColor, size: 20),
              onSelected: (v) {
                if (v == 'edit') _editPost(post);
                if (v == 'delete') _confirmDeletePost(postId);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ]),
        if (content.isNotEmpty &&
            !content.startsWith('@post:')) ...[
          const SizedBox(height: 10),
          Text(content, style: TextStyle(color: context.textColor, fontSize: 13, height: 1.5)),
        ],
        if (mediaUrl.isNotEmpty && mediaType == 'audio') ...[
          const SizedBox(height: 10),
          VoiceNotePlayer(mediaUrl: mediaUrl),
        ],
        const SizedBox(height: 8),
        // Tap Comment to open replies in a sheet (not nested under the post).
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _toggleLike(postId),
                child: Text(
                  likeCount > 0 ? 'Like · $likeCount' : 'Like',
                  style: TextStyle(
                    color: likedByMe ? context.accentColor : context.greyLColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _openComments(context, post),
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
                _formatTime(createdAt),
                style: TextStyle(color: context.greyColor, fontSize: 11),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildAnnouncementsTab() {
    if (_loadingChannels || _loadingAnnouncements) {
      return Center(child: CircularProgressIndicator(color: context.accentColor));
    }
    if (_announcementChannels.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.campaign_outlined, color: context.greyColor, size: 56),
        const SizedBox(height: 12),
        Text('No announcements yet', style: TextStyle(color: context.textColor, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Teacher announcements will appear here.', style: TextStyle(color: context.greyColor, fontSize: 13)),
      ]));
    }
    if (_announcementPosts.isEmpty) {
      return RefreshIndicator(
        color: context.accentColor,
        onRefresh: _loadAnnouncements,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _announcementBanner(),
            const SizedBox(height: 24),
            Center(child: Column(children: [
              Icon(Icons.campaign_outlined, color: context.greyColor, size: 48),
              const SizedBox(height: 12),
              Text('No announcements yet', style: TextStyle(color: context.textColor, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Check back later for teacher updates.', style: TextStyle(color: context.greyColor, fontSize: 13)),
            ])),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: context.accentColor,
      onRefresh: _loadAnnouncements,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _announcementPosts.length + 1,
        separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 12 : 12),
        itemBuilder: (_, i) {
          if (i == 0) return _announcementBanner();
          final post = _announcementPosts[i - 1] as Map<String, dynamic>;
          return _buildAnnouncementPost(post);
        },
      ),
    );
  }

  Widget _announcementBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: context.accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.campaign_outlined, color: context.accentColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Teacher Announcements',
            style: TextStyle(color: context.textColor, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, color: Color(0xFF6366F1), size: 12),
            SizedBox(width: 4),
            Text('Read only', style: TextStyle(color: Color(0xFF6366F1), fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildAnnouncementPost(Map<String, dynamic> post) {
    final author = post['author_name']?.toString() ?? 'Teacher';
    final content = post['content']?.toString() ?? '';
    final createdAt = post['created_at']?.toString() ?? '';
    final channelName = post['channel_name']?.toString() ?? '';
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
              AuthorAvatar(
                pictureUrl: post['author_picture']?.toString() ??
                    post['profile_picture']?.toString(),
                name: author,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author,
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [channelName, _formatTime(createdAt)]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(color: context.greyColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(content, style: TextStyle(color: context.textColor, fontSize: 13, height: 1.5)),
          ],
          if (mediaUrl.isNotEmpty && mediaType == 'audio') ...[
            const SizedBox(height: 10),
            VoiceNotePlayer(mediaUrl: mediaUrl, label: 'Voice announcement'),
          ],
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return iso; }
  }
}
