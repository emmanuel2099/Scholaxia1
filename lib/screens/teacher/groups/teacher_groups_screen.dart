import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import '../teacher_shared.dart';

class TeacherGroupsScreen extends StatefulWidget {
  const TeacherGroupsScreen({super.key});

  @override
  State<TeacherGroupsScreen> createState() => _TeacherGroupsScreenState();
}

class _TeacherGroupsScreenState extends State<TeacherGroupsScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;
  String? _teacherName;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.listSchoolGroups(),
        _api.listLiveSessionRequests(),
        _api.getTeacherMe(),
        _api.unreadNotificationCount(),
      ]);
      final groups = (results[0] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final requests = (results[1] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) {
        setState(() {
          _groups = groups;
          _students = requests;
          _teacherName = (results[2] as Map)['full_name']?.toString();
          _unread = results[3] as int;
          _loading = false;
        });
        teacherUnreadCount.value = _unread;
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateSheet() async {
    final schoolCtrl = TextEditingController(text: 'Scholaxia');
    final nameCtrl = TextEditingController();
    final emailsCtrl = TextEditingController();
    final selected = <String>{};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
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
                      'Create school group',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _field(ctx, schoolCtrl, 'School name', 'e.g. Greenfield Academy'),
                    const SizedBox(height: 12),
                    _field(ctx, nameCtrl, 'Group name', 'e.g. SS2 Physics A'),
                    const SizedBox(height: 12),
                    _field(
                      ctx,
                      emailsCtrl,
                      'Student emails (optional)',
                      'student1@email.com, student2@email.com',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Or pick assigned students',
                      style: TextStyle(
                        color: context.textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_students.isEmpty)
                      Text(
                        'No assigned students yet — add students by email above.',
                        style: TextStyle(color: context.greyColor, fontSize: 12),
                      )
                    else
                      ..._students.map((s) {
                        final sid = s['student_id']?.toString() ?? '';
                        final name = s['student_name']?.toString() ??
                            s['full_name']?.toString() ??
                            'Student';
                        final checked = selected.contains(sid);
                        return CheckboxListTile(
                          value: checked,
                          activeColor: context.accentColor,
                          title: Text(name,
                              style: TextStyle(
                                  color: context.textColor, fontSize: 14)),
                          onChanged: sid.isEmpty
                              ? null
                              : (v) {
                                  setSheet(() {
                                    if (v == true) {
                                      selected.add(sid);
                                    } else {
                                      selected.remove(sid);
                                    }
                                  });
                                },
                        );
                      }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final school = schoolCtrl.text.trim();
                          final name = nameCtrl.text.trim();
                          if (school.isEmpty || name.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Enter school and group name.')),
                            );
                            return;
                          }
                          try {
                            final emails = emailsCtrl.text
                                .split(RegExp(r'[,;\s]+'))
                                .map((e) => e.trim())
                                .where((e) => e.contains('@'))
                                .toList();
                            await _api.createSchoolGroup(
                              schoolName: school,
                              name: name,
                              studentIds: selected.toList(),
                              studentEmails: emails,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _load();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Group created!')),
                              );
                            }
                          } on ApiException catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Create group',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    schoolCtrl.dispose();
    nameCtrl.dispose();
  }

  Widget _field(BuildContext ctx, TextEditingController ctrl, String label,
      String hint,
      {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: context.textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: TextStyle(color: context.textColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.greyLColor),
            filled: true,
            fillColor: context.surfColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.borderColor),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showGroupSheet(Map<String, dynamic> g) async {
    final groupId = g['id']?.toString() ?? '';
    if (groupId.isEmpty) return;

    Map<String, dynamic> detail = g;
    try {
      detail = await _api.getSchoolGroup(groupId);
    } catch (_) {}

    final members = (detail['members'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    final emailsCtrl = TextEditingController();

    if (!mounted) return;
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
                Text(
                  detail['name']?.toString() ?? 'Group',
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail['school_name']?.toString() ?? '',
                  style: TextStyle(color: context.greyColor, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Text('Members (${members.length})',
                    style: TextStyle(
                        color: context.textColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (members.isEmpty)
                  Text('No students in this group yet.',
                      style: TextStyle(color: context.greyColor, fontSize: 13))
                else
                  ...members.map((m) {
                    final name = m['name']?.toString() ?? 'Student';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: context.accentColor.withOpacity(0.15),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'S',
                          style: TextStyle(
                              color: context.accentColor,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(name,
                          style: TextStyle(color: context.textColor)),
                    );
                  }),
                const SizedBox(height: 16),
                _field(ctx, emailsCtrl, 'Add students by email',
                    'student@email.com'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final emails = emailsCtrl.text
                          .split(RegExp(r'[,;\s]+'))
                          .map((e) => e.trim())
                          .where((e) => e.contains('@'))
                          .toList();
                      if (emails.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Enter at least one email.')),
                        );
                        return;
                      }
                      try {
                        await _api.updateSchoolGroup(
                          groupId,
                          studentIds: (detail['student_ids'] as List?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              members
                                  .map((m) => m['student_id']?.toString() ?? '')
                                  .where((id) => id.isNotEmpty)
                                  .toList(),
                          studentEmails: emails,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Students added!')),
                          );
                        }
                      } on ApiException catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(e.message),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Add to group',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    emailsCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.accentColor))
          : RefreshIndicator(
              color: context.accentColor,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Column(
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
                            greeting: 'School Groups',
                            subtitle:
                                'Create groups and host classes for your students.',
                            icon: Icons.groups_rounded,
                            badge: _groups.isNotEmpty
                                ? '${_groups.length} GROUPS'
                                : null,
                          ),
                          const StudentSectionTitle(title: 'Your groups'),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _showCreateSheet,
                                icon: const Icon(Icons.add, size: 20),
                                label: const Text('Create new group',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.accentColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_groups.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.groups_outlined,
                                        color: context.greyColor, size: 48),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No groups yet',
                                      style: TextStyle(
                                        color: context.textColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Tap Create new group to get started.',
                                      style: TextStyle(
                                          color: context.greyColor,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ..._groups.map(_groupCard),
                          const SizedBox(height: 110),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _groupCard(Map<String, dynamic> g) {
    final name = g['name']?.toString() ?? 'Group';
    final school = g['school_name']?.toString() ?? '';
    final count = g['member_count'] as int? ??
        (g['members'] as List?)?.length ??
        0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showGroupSheet(g),
          borderRadius: BorderRadius.circular(20),
          child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: context.accentColor.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppGradients.primaryButton,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.groups_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: context.textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '$school · $count members',
                    style: TextStyle(color: context.greyColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.greyColor),
          ],
        ),
          ),
        ),
      ),
    );
  }
}
