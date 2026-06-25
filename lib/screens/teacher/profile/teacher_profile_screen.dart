import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/theme_toggle_tile.dart';
import '../teacher_shared.dart';

class TeacherProfileScreen extends StatefulWidget {
  final bool embeddedInShell;

  const TeacherProfileScreen({super.key, this.embeddedInShell = false});

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;
  int _unread = 0;

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
      final results = await Future.wait([
        _api.getTeacherMe(),
        _api.unreadNotificationCount().catchError((_) => 0),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Map<String, dynamic>;
        _unread = results[1] as int;
        _loading = false;
      });
      teacherUnreadCount.value = results[1] as int;
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is ApiException ? e.message : 'Could not load profile.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embeddedInShell) {
      return Scaffold(
        backgroundColor: context.bgColor,
        body: SafeArea(child: _buildBody(context, showTopBar: true)),
      );
    }

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('My Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _buildBody(context, showTopBar: false),
    );
  }

  Widget _buildBody(BuildContext context, {required bool showTopBar}) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.accentColor),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.greyColor)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final name = _profile?['full_name']?.toString() ?? 'Teacher';
    final email = _profile?['email']?.toString() ?? '';
    final joined = _profile?['joined']?.toString() ?? '';
    final approved = _profile?['is_approved'] == true;

    return RefreshIndicator(
      color: context.accentColor,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (showTopBar) ...[
            const SizedBox(height: 16),
            TeacherTopBar(
              api: _api,
              teacherName: name,
              unreadCount: _unread,
            ),
            const SizedBox(height: 20),
            Text('My Profile',
                style: TextStyle(
                    color: context.textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Your account details.',
                style: TextStyle(color: context.greyColor, fontSize: 13)),
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: context.accentColor.withOpacity(0.15),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'T',
                    style: TextStyle(
                        color: context.accentColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 14),
                Text(name,
                    style: TextStyle(
                        color: context.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(email,
                      style: TextStyle(color: context.greyColor, fontSize: 13)),
                ],
                if (joined.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Joined $joined',
                      style: TextStyle(color: context.greyColor, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (approved ? context.accentColor : context.greyColor)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    approved ? 'Approved teacher' : 'Pending approval',
                    style: TextStyle(
                      color: approved ? context.accentColor : context.greyColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const ThemeToggleTile(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => TeacherUtils.teacherLogout(context, _api),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Log out', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}
