import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'group_chat_screen.dart';

/// Groups list + create — matches desktop Groups tab APIs:
/// - GET /student-groups/mine
/// - GET /student-groups/community-listed (filter !is_member → join list)
/// - GET /school-groups/student/mine
class GroupsPanel extends StatefulWidget {
  const GroupsPanel({super.key});

  @override
  State<GroupsPanel> createState() => _GroupsPanelState();
}

class _GroupsPanelState extends State<GroupsPanel> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _discover = [];
  List<Map<String, dynamic>> _school = [];
  bool _loading = true;
  String _query = '';

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _listInCommunity = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(Map<String, dynamic> g) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final name = g['name']?.toString().toLowerCase() ?? '';
    final desc = g['description']?.toString().toLowerCase() ?? '';
    final creator = g['creator_name']?.toString().toLowerCase() ?? '';
    return name.contains(q) || desc.contains(q) || creator.contains(q);
  }

  List<Map<String, dynamic>> get _filteredMine =>
      _mine.where(_matchesQuery).toList();

  List<Map<String, dynamic>> get _filteredDiscover =>
      _discover.where(_matchesQuery).toList();

  List<Map<String, dynamic>> get _filteredSchool =>
      _school.where(_matchesQuery).toList();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final mineFuture = _api.myStudentGroups();
      final schoolFuture = _safeList(_api.mySchoolGroups());
      final listedFuture = _api.communityListedGroups();
      final results = await Future.wait<dynamic>([
        mineFuture,
        schoolFuture,
        listedFuture,
      ]);
      if (mounted) {
        setState(() {
          _mine = _toMaps(results[0]);
          _school = _toMaps(results[1]);
          _discover = _toMaps(results[2])
              .where((g) => g['is_member'] != true)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _toMaps(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<dynamic>> _safeList(Future<List<dynamic>> call) async {
    try {
      return await call;
    } catch (_) {
      return [];
    }
  }

  Future<void> _createGroup() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a group name.')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final res = await _api.createStudentGroup(
        name: name,
        description: _descCtrl.text.trim(),
        isCommunityListed: _listInCommunity,
      );
      _nameCtrl.clear();
      _descCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Group submitted.')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Could not create group.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _requestJoin(Map<String, dynamic> group) async {
    final id = group['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final res = await _api.requestJoinStudentGroup(
        id,
        message: 'I would like to join this group.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Join request sent.')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Could not send request.'),
          ),
        );
      }
    }
  }

  Future<void> _manageJoinRequests(Map<String, dynamic> group) async {
    final groupId = group['id']?.toString() ?? '';
    if (groupId.isEmpty) return;
    try {
      final reqs = await _api.listGroupJoinRequests(groupId);
      if (!mounted) return;
      if (reqs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pending join requests.')),
        );
        return;
      }
      final picked = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: context.cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Pending join requests',
                    style: TextStyle(
                      color: ctx.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...reqs.whereType<Map>().map((r) {
                  final map = Map<String, dynamic>.from(r);
                  final name = map['name']?.toString() ?? 'Student';
                  final msg = map['message']?.toString() ?? '';
                  return ListTile(
                    title: Text(name, style: TextStyle(color: ctx.textColor)),
                    subtitle: msg.isNotEmpty
                        ? Text(msg, style: TextStyle(color: ctx.greyColor, fontSize: 12))
                        : null,
                    trailing: TextButton(
                      onPressed: () => Navigator.pop(ctx, map),
                      child: Text('Approve', style: TextStyle(color: ctx.accentColor)),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
      if (picked == null) return;
      final requestId = picked['id']?.toString() ?? '';
      if (requestId.isEmpty) return;
      final res = await _api.approveGroupJoinRequest(groupId, requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Student approved.')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Could not load requests.'),
          ),
        );
      }
    }
  }

  void _openChat(Map<String, dynamic> group) {
    final id = group['id']?.toString() ?? '';
    if (id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          groupId: id,
          groupName: group['name']?.toString() ?? 'Group',
        ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: context.accentColor));
    }

    final mine = _filteredMine;
    final discover = _filteredDiscover;
    final school = _filteredSchool;
    final hasQuery = _query.trim().isNotEmpty;

    return Stack(
      children: [
        RefreshIndicator(
          color: context.accentColor,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _searchField(context),
              const SizedBox(height: 16),
              _sectionTitle(context, 'Your groups'),
              const SizedBox(height: 8),
              if (mine.isEmpty)
                _emptyHint(
                  context,
                  hasQuery
                      ? 'No groups match “${_query.trim()}”'
                      : 'You have not joined a group yet',
                  hasQuery
                      ? 'Try another name, or clear the search.'
                      : 'Tap + below to create one, or join from Discover groups.',
                )
              else
                ...mine.map(
                    (g) => _studentGroupCard(context, g, isMineSection: true)),
              const SizedBox(height: 20),
              _sectionTitle(context, 'Discover groups'),
              const SizedBox(height: 4),
              Text(
                'Open groups listed in Community — tap Join group to request access.',
                style: TextStyle(color: context.greyColor, fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (discover.isEmpty)
                _emptyHint(
                  context,
                  hasQuery
                      ? 'No discover groups match “${_query.trim()}”'
                      : 'No open groups right now',
                  hasQuery
                      ? 'Try a different search.'
                      : 'Create one and list it in the feed for others to join.',
                )
              else
                ...discover.map(
                    (g) => _studentGroupCard(context, g, isMineSection: false)),
              if (_school.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionTitle(context, 'School groups'),
                const SizedBox(height: 4),
                Text(
                  'Added by your school — live class codes appear in the access code popup.',
                  style: TextStyle(color: context.greyColor, fontSize: 12),
                ),
                const SizedBox(height: 8),
                if (school.isEmpty)
                  _emptyHint(
                    context,
                    'No school groups match “${_query.trim()}”',
                    'Try another search.',
                  )
                else
                  ...school.map((g) => _schoolGroupCard(context, g)),
              ],
            ],
          ),
        ),
        Positioned(
          right: 20,
          bottom: 88,
          child: FloatingActionButton.extended(
            onPressed: _showCreateSheet,
            backgroundColor: context.accentColor,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'New group',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      style: TextStyle(color: context.textColor),
      decoration: InputDecoration(
        hintText: 'Search groups by name…',
        hintStyle: TextStyle(color: context.greyLColor),
        prefixIcon: Icon(Icons.search_rounded, color: context.greyColor),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
                icon: Icon(Icons.close_rounded, color: context.greyColor),
              ),
        filled: true,
        fillColor: context.cardColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.accentColor, width: 1.5),
        ),
      ),
    );
  }

  Future<void> _showCreateSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Create a group',
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'New groups need admin approval before they become active.',
                  style: TextStyle(color: context.greyColor, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(
                    hintText: 'Group name',
                    hintStyle: TextStyle(color: context.greyLColor),
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
                  controller: _descCtrl,
                  maxLines: 2,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(
                    hintText: 'Description (optional)',
                    hintStyle: TextStyle(color: context.greyLColor),
                    filled: true,
                    fillColor: context.surfColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _listInCommunity,
                        onChanged: (v) =>
                            setState(() => _listInCommunity = v ?? true),
                        activeColor: context.accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'List for others to join after admin approval',
                        style: TextStyle(color: context.textColor, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _creating
                        ? null
                        : () async {
                            await _createGroup();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _creating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create group',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        color: context.textColor,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _studentGroupCard(
    BuildContext context,
    Map<String, dynamic> g, {
    required bool isMineSection,
  }) {
    final name = g['name']?.toString() ?? 'Group';
    final desc = g['description']?.toString() ?? 'Student study group';
    final count = g['member_count'] ?? 0;
    final creator = g['creator_name']?.toString() ?? '';
    final approved = g['is_approved'] == true;
    final isMember = g['is_member'] == true || isMineSection;
    final isAdmin = g['is_admin'] == true;
    final pending = g['pending_request'] == true;
    final listed = g['is_community_listed'] == true;

    var meta = '$desc · $count member${count == 1 ? '' : 's'}';
    if (!isMineSection && creator.isNotEmpty) meta += ' · by $creator';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'G',
                  style: TextStyle(
                    color: context.accentColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!approved) _badge('Pending approval', const Color(0xFFF59E0B)),
                        if (isAdmin) _badge('Admin', context.accentColor),
                        if (listed) _badge('Listed', const Color(0xFF22C55E)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(meta, style: TextStyle(color: context.greyColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isMember && approved) ...[
                ElevatedButton(
                  onPressed: () => _openChat(g),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Open chat'),
                ),
                if (isAdmin)
                  OutlinedButton(
                    onPressed: () => _manageJoinRequests(g),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.accentColor,
                      side: BorderSide(color: context.accentColor.withOpacity(0.5)),
                    ),
                    child: const Text('Requests'),
                  ),
              ] else if (isMember && !approved)
                Text(
                  'Waiting for Scholaxia admin approval',
                  style: TextStyle(color: context.greyColor, fontSize: 12),
                )
              else if (pending)
                _badge('Request pending', context.greyColor)
              else if (!isMember && approved)
                ElevatedButton(
                  onPressed: () => _requestJoin(g),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Join group'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _schoolGroupCard(BuildContext context, Map<String, dynamic> g) {
    final school = g['school_name']?.toString() ?? 'School';
    final name = g['name']?.toString() ?? 'Group';
    final teacher = g['teacher_name']?.toString() ?? 'Teacher';
    final count = g['member_count'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.school_rounded, color: Color(0xFF3B82F6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$school — $name',
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Teacher: $teacher · $count students',
                  style: TextStyle(color: context.greyColor, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Live class codes appear in the access code popup.',
                  style: TextStyle(color: context.greyColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _emptyHint(BuildContext context, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surfColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          children: [
            Icon(Icons.group_off_outlined, color: context.greyColor, size: 32),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: context.textColor, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center,
                style: TextStyle(color: context.greyColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
