import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../auth/exam_subject_setup_screen.dart';
import '../../auth/login_screen.dart';
import '../notifications/notifications_screen.dart';
import 'about_scholaxia_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  StudentProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _api.getStudentProfile();
      if (mounted) setState(() { _profile = p; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _logout() async {
    await _api.clearTokens();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.accentColor))
          : _error != null
              ? _buildError(context)
              : RefreshIndicator(
                  color: context.accentColor,
                  onRefresh: _load,
                  child: _buildContent(context),
                ),
    );
  }

  Widget _buildError(BuildContext context) {
    final isAuthError = _error != null &&
        (_error!.contains('Not logged in') ||
            (_error!.contains('profile') && _error!.contains('404')));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(isAuthError ? Icons.person_outline : Icons.error_outline,
              color: context.greyColor, size: 48),
          const SizedBox(height: 12),
          Text(isAuthError ? 'Profile not set up yet' : 'Could not load profile',
              style: TextStyle(color: context.textColor, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(isAuthError
              ? 'Your student profile is being set up. Please log out and log back in.'
              : (_error ?? ''),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.greyColor, fontSize: 12)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
            style: ElevatedButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: context.isDark ? AppColors.background : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Retry'),
          ),
          if (isAuthError) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await _api.clearTokens();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
              },
              child: Text('Log out', style: TextStyle(color: context.greyColor)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final p = _profile!;
    final initials = p.fullName.isNotEmpty
        ? p.fullName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';
    final examSet = p.examType != null && p.examType!.isNotEmpty;
    final levelSet = p.educationLevel != null && p.educationLevel!.isNotEmpty;
    final profileIncomplete = !examSet || !levelSet || p.subjects.isEmpty;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _heroHeader(context, p, initials)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _statsCard(context),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (profileIncomplete) ...[
                _incompleteBanner(context),
                const SizedBox(height: 16),
              ],
              _sectionTitle(context, 'Study details'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _detailCard(
                    context,
                    icon: Icons.school_rounded,
                    label: 'Exam target',
                    value: examSet ? p.examType! : 'Not set',
                    muted: !examSet,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _detailCard(
                    context,
                    icon: Icons.menu_book_rounded,
                    label: 'Education',
                    value: levelSet ? p.educationLevel! : 'Not set',
                    muted: !levelSet,
                  )),
                ],
              ),
              if (p.subjects.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionTitle(context, 'My subjects'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: p.subjects.map((s) => _subjectChip(context, s)).toList(),
                ),
              ],
              const SizedBox(height: 24),
              _sectionTitle(context, 'Preferences'),
              const SizedBox(height: 10),
              _settingsGroup(context, [
                _settingsRow(
                  context,
                  Icons.notifications_outlined,
                  'Notifications',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  ),
                ),
                _settingsRow(
                  context,
                  context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  context.isDark ? 'Light mode' : 'Dark mode',
                  trailing: Switch.adaptive(
                    value: context.isDark,
                    activeColor: context.accentColor,
                    onChanged: (_) => setState(() => themeNotifier.toggle()),
                  ),
                  onTap: () => setState(() => themeNotifier.toggle()),
                ),
              ]),
              const SizedBox(height: 16),
              _sectionTitle(context, 'About'),
              const SizedBox(height: 10),
              _settingsGroup(context, [
                _settingsRow(
                  context,
                  Icons.info_outline_rounded,
                  'About Scholaxia',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutScholaxiaScreen()),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _logoutButton(context),
              const SizedBox(height: 100),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _heroHeader(BuildContext context, StudentProfile p, String initials) {
    return Container(
      width: double.infinity,
      color: context.headerColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  Text('Profile',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      )),
                  const Spacer(),
                  _planBadge(context, p.hasActiveSubscription),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.accentColor.withOpacity(0.35),
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: context.accentColor.withOpacity(0.12),
                  child: Text(initials,
                      style: TextStyle(
                        color: context.accentColor,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      )),
                ),
              ),
              const SizedBox(height: 16),
              Text(p.fullName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  )),
              const SizedBox(height: 6),
              Text(p.email,
                  style: TextStyle(
                    color: context.greyColor,
                    fontSize: 14,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planBadge(BuildContext context, bool premium) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: premium
            ? context.accentColor.withOpacity(0.12)
            : context.surfColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: premium
              ? context.accentColor.withOpacity(0.35)
              : context.borderColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            premium ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
            size: 14,
            color: premium ? context.accentColor : context.greyColor,
          ),
          const SizedBox(width: 5),
          Text(
            premium ? 'Premium' : 'Free plan',
            style: TextStyle(
              color: premium ? context.accentColor : context.greyColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDark ? 0.25 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _statItem(context, Icons.quiz_outlined, '0', 'Exams taken'),
          _statDivider(context),
          _statItem(context, Icons.schedule_rounded, '0', 'Study hours'),
          _statDivider(context),
          _statItem(context, Icons.trending_up_rounded, '0%', 'Avg score'),
        ],
      ),
    );
  }

  Widget _statDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: context.borderColor,
    );
  }

  Widget _statItem(BuildContext context, IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: context.accentColor.withOpacity(0.85)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              )),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.greyColor, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _incompleteBanner(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExamSubjectSetupScreen(popOnComplete: true)),
        );
        if (mounted) _load();
      },
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.accentColor.withOpacity(context.isDark ? 0.15 : 0.12),
            context.accentColor.withOpacity(context.isDark ? 0.08 : 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.accentColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.edit_note_rounded, color: context.accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Complete your profile',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text('Set your exam target and education level to personalize your study plan.',
                    style: TextStyle(color: context.greyColor, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title,
        style: TextStyle(
          color: context.textColor,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ));
  }

  Widget _detailCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool muted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: context.accentColor, size: 18),
          ),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(color: context.greyColor, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted ? context.greyColor : context.textColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.25,
              )),
        ],
      ),
    );
  }

  Widget _subjectChip(BuildContext context, String subject) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: context.surfColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.borderColor),
      ),
      child: Text(subject,
          style: TextStyle(
            color: context.textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          )),
    );
  }

  Widget _settingsGroup(BuildContext context, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: List.generate(rows.length, (i) => Column(
          children: [
            rows[i],
            if (i < rows.length - 1)
              Divider(height: 1, indent: 56, color: context.borderColor),
          ],
        )),
      ),
    );
  }

  Widget _settingsRow(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.surfColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: context.textColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    )),
              ),
              trailing ??
                  Icon(Icons.chevron_right_rounded, color: context.greyColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoutButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _logout,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(context.isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.35)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
              SizedBox(width: 8),
              Text('Log out',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
