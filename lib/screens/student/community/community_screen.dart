import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'new_post_screen.dart';
import 'join_channel_screen.dart';
import 'post_comments_sheet.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _api = ApiService();
  List<dynamic> _channels = [];
  List<dynamic> _posts = [];
  List<dynamic> _pinnedPosts = [];
  List<dynamic> _announcementPosts = [];
  bool _loadingChannels = true;
  bool _loadingPosts = false;
  bool _loadingAnnouncements = false;
  int _tabIndex = 0;
  String _generalChannelId = '';

  String _generalChannelName = '';
  final Map<String, int> _commentCounts = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging && _tabCtrl.index != _tabIndex) {
        setState(() => _tabIndex = _tabCtrl.index);
        if (_tabCtrl.index == 1) _loadAnnouncements();
      }
    });
    _loadChannels();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    setState(() => _loadingChannels = true);
    try {
      final data = await _api.communityChannels();
      if (!mounted) return;
      setState(() { _channels = data; _loadingChannels = false; });
      final general = data.firstWhere(
        (c) {
          final n = (c as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
          return !n.contains('teacher') && !n.contains('announcement') && !n.contains('notice');
        },
        orElse: () => data.isNotEmpty ? data.first : null,
      );
      if (general != null) {
        _generalChannelId = (general as Map<String, dynamic>)['id']?.toString() ?? '';
        _generalChannelName = (general as Map<String, dynamic>)['name']?.toString() ?? 'General';
        // Auto-join the channel silently, then load posts
        try { await _api.joinChannel(channelId: _generalChannelId); } catch (_) {}
        _loadPosts();        _loadPinnedPosts();
        _loadAnnouncements();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingChannels = false);
    }
  }

  Future<void> _loadPosts({bool keepExistingOnError = true}) async {
    if (_generalChannelId.isEmpty) return;
    setState(() => _loadingPosts = true);
    try {
      final data = await _api.listPosts(channelId: _generalChannelId);
      if (mounted) setState(() { _posts = data; _loadingPosts = false; });
      await _loadCommentCounts();
    } catch (_) {
      if (mounted) {
        setState(() {
          if (!keepExistingOnError) _posts = [];
          _loadingPosts = false;
        });
      }
    }
  }

  void _prependPost(Map<String, dynamic> post) {
    final id = post['id']?.toString() ?? '';
    setState(() {
      _posts = [
        post,
        ..._posts.where((p) => (p as Map<String, dynamic>)['id']?.toString() != id),
      ];
    });
  }

  Future<void> _handleNewPostResult(dynamic result) async {
    if (result is Map<String, dynamic>) {
      _prependPost(result);
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
      final messages = await _api.getMessages(channelId: _generalChannelId);
      final counts = <String, int>{};
      for (final m in messages) {
        if (m is! Map) continue;
        final content = m['content']?.toString() ?? '';
        final match = RegExp(r'^@post:([^\s]+)').firstMatch(content);
        if (match != null) {
          final id = match.group(1)!;
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }
      if (mounted) setState(() {
        _commentCounts
          ..clear()
          ..addAll(counts);
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
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton(
              onPressed: _generalChannelId.isEmpty ? null : _openNewPost,
              backgroundColor: context.accentColor,
              foregroundColor: context.isDark ? AppColors.background : Colors.white,
              child: const Icon(Icons.send_rounded),
            )
          : null,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(context),
          _buildTabBar(context),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildGeneralTab(context),
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(children: [
        Container(width: 32, height: 32,
          decoration: BoxDecoration(color: context.accentColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.school_outlined, color: context.accentColor, size: 18)),
        const SizedBox(width: 8),
        Text('Scholaxia',
            style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
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
        tabs: const [Tab(text: 'General'), Tab(text: 'Teacher Announcements')],
      ),
    );
  }

  Widget _buildGeneralTab(BuildContext context) {
    if (_loadingChannels) {
      return Center(child: CircularProgressIndicator(color: context.accentColor));
    }
    return RefreshIndicator(
      color: context.accentColor,
      onRefresh: () async { await _loadChannels(); },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_pinnedPosts.isNotEmpty) ...[
            Text('Pinned Posts', style: TextStyle(color: context.textColor, fontSize: 15, fontWeight: FontWeight.bold)),
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
            Text('Recent Activity', style: TextStyle(color: context.textColor, fontSize: 15, fontWeight: FontWeight.bold)),
            TextButton(onPressed: _loadPosts, child: Text('Refresh', style: TextStyle(color: context.accentColor, fontSize: 12))),
          ]),
          const SizedBox(height: 8),
          if (_loadingPosts)
            Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: context.accentColor)))
          else if (_posts.isEmpty)
            _buildEmptyFeed(context)
          else
            ..._posts.map((p) {
              final post = p as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildPostFromApi(context, post),
              );
            }),
          const SizedBox(height: 80),
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
        Text('Be the first to post in this channel!', style: TextStyle(color: context.greyColor, fontSize: 13)),
      ])),
    );
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
    final initial = authorName.isNotEmpty ? authorName[0].toUpperCase() : 'U';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isPinned ? context.accentColor : context.borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 20, backgroundColor: context.accentColor.withOpacity(0.15),
              child: Text(initial, style: TextStyle(color: context.accentColor, fontWeight: FontWeight.bold))),
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
          Icon(Icons.more_vert, color: context.greyColor, size: 18),
        ]),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(content, style: TextStyle(color: context.textColor, fontSize: 13, height: 1.5)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          GestureDetector(
            onTap: () => _toggleLike(postId),
            child: Row(children: [
              Icon(likedByMe ? Icons.thumb_up : Icons.thumb_up_outlined,
                  color: likedByMe ? context.accentColor : context.greyColor, size: 15),
              const SizedBox(width: 4),
              Text('$likeCount',
                  style: TextStyle(
                      color: likedByMe ? context.accentColor : context.greyColor,
                      fontSize: 12,
                      fontWeight: likedByMe ? FontWeight.w600 : FontWeight.normal)),
            ]),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => _openComments(context, post),
            child: Row(children: [
              Icon(Icons.chat_bubble_outline, color: context.greyColor, size: 15),
              const SizedBox(width: 4),
              Text(commentCount > 0 ? 'Comment ($commentCount)' : 'Comment',
                  style: TextStyle(color: context.greyColor, fontSize: 12)),
            ]),
          ),
        ]),
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
              CircleAvatar(
                radius: 18,
                backgroundColor: context.accentColor.withOpacity(0.15),
                child: Icon(Icons.school_outlined, color: context.accentColor, size: 18),
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
