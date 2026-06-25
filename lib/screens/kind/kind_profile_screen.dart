import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/theme_toggle_tile.dart';
import '../auth/role_select_screen.dart';
import 'kind_shared.dart';

class KindProfileScreen extends StatefulWidget {
  const KindProfileScreen({super.key});

  @override
  State<KindProfileScreen> createState() => _KindProfileScreenState();
}

class _KindProfileScreenState extends State<KindProfileScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _api.getKindMe();
      if (mounted) setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _api.clearTokens();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?['full_name']?.toString() ?? 'Learner';
    final email = _profile?['email']?.toString() ?? '';
    final age = _profile?['age_group']?.toString() ?? '';
    final parent = _profile?['parent_email']?.toString() ?? '';

    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: KidColors.accent))
            : RefreshIndicator(
                color: KidColors.accent,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Text('My Profile',
                        style: TextStyle(
                            color: context.textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Center(
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: KidColors.accent.withOpacity(0.2),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'K',
                          style: const TextStyle(
                              color: KidColors.accent,
                              fontSize: 32,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(name,
                          style: TextStyle(
                              color: context.textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (age.isNotEmpty)
                      Center(
                        child: Text('Ages $age',
                            style: TextStyle(
                                color: context.greyColor, fontSize: 13)),
                      ),
                    const SizedBox(height: 24),
                    _row(context, Icons.mail_outline, 'Email', email),
                    if (parent.isNotEmpty)
                      _row(context, Icons.family_restroom_outlined,
                          'Parent email', parent),
                    const SizedBox(height: 20),
                    ThemeToggleTile(accentColor: KidColors.accent),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: const Text('Log out',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: KidColors.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: context.greyColor, fontSize: 11)),
                  Text(value,
                      style: TextStyle(
                          color: context.textColor, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
