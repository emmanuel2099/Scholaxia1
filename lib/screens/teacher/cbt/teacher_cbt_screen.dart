import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../teacher_shared.dart';

class TeacherCbtScreen extends StatefulWidget {
  const TeacherCbtScreen({super.key});

  @override
  State<TeacherCbtScreen> createState() => _TeacherCbtScreenState();
}

class _TeacherCbtScreenState extends State<TeacherCbtScreen> {
  final _api = ApiService();
  String _selectedTab = 'My Exams';
  final _tabs = ['My Exams', 'Results'];
  bool _loading = true;
  String? _teacherName;
  int _unread = 0;
  List<Map<String, dynamic>> _exams = [];
  Map<String, dynamic>? _selectedResults;
  bool _loadingResults = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getTeacherMe(),
        _api.unreadNotificationCount(),
        _api.teacherSchoolExams(),
      ]);
      if (!mounted) return;
      setState(() {
        _teacherName = (results[0] as Map)['full_name']?.toString();
        _unread = results[1] as int;
        _exams = (results[2] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
      teacherUnreadCount.value = results[1] as int;
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadResults(String examId) async {
    setState(() => _loadingResults = true);
    try {
      final data = await _api.schoolExamResults(examId);
      if (mounted) setState(() => _selectedResults = data);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingResults = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TeacherTopBar(
                api: _api,
                teacherName: _teacherName,
                unreadCount: _unread,
                showBack: true,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scholaxia Exams',
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      'Review student scores for your school exams.',
                      style: TextStyle(color: context.greyColor, fontSize: 13)),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _tabs.map((t) {
                        final sel = t == _selectedTab;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedTab = t;
                            _selectedResults = null;
                          }),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 9),
                            decoration: BoxDecoration(
                              color: sel ? accent : context.surfColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(t,
                                style: TextStyle(
                                    color:
                                        sel ? Colors.black : context.greyLColor,
                                    fontSize: 13,
                                    fontWeight: sel
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : _selectedTab == 'My Exams'
                      ? _examList()
                      : _resultsView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _examList() {
    if (_exams.isEmpty) {
      return RefreshIndicator(
        color: context.accentColor,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Center(
              child: Text('No school exams yet.',
                  style: TextStyle(color: context.greyColor),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: context.accentColor,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        itemCount: _exams.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final e = _exams[i];
          final subject = e['subject']?.toString() ?? '';
          final color = TeacherUtils.subjectColor(subject, context);
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e['title']?.toString() ?? 'Exam',
                    style: TextStyle(
                        color: context.textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Text(subject, style: TextStyle(color: color, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        color: context.greyColor, size: 14),
                    const SizedBox(width: 4),
                    Text('${e['duration_minutes'] ?? '—'} mins',
                        style:
                            TextStyle(color: context.greyColor, fontSize: 12)),
                    const SizedBox(width: 12),
                    Icon(Icons.quiz_outlined,
                        color: context.greyColor, size: 14),
                    const SizedBox(width: 4),
                    Text('${e['total_questions'] ?? '—'} questions',
                        style:
                            TextStyle(color: context.greyColor, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _selectedTab = 'Results');
                    _loadResults(e['id']?.toString() ?? '');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.accentColor,
                    side: BorderSide(color: context.accentColor),
                  ),
                  child: const Text('View Results'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _resultsView() {
    if (_loadingResults) {
      return Center(
          child: CircularProgressIndicator(color: context.accentColor));
    }
    if (_selectedResults == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Select an exam from My Exams to view results.',
              style: TextStyle(color: context.greyColor)),
          const SizedBox(height: 16),
          ..._exams.map((e) => ListTile(
                title: Text(e['title']?.toString() ?? 'Exam',
                    style: TextStyle(color: context.textColor)),
                subtitle: Text(e['subject']?.toString() ?? '',
                    style: TextStyle(color: context.greyColor)),
                trailing: Icon(Icons.chevron_right, color: context.accentColor),
                onTap: () => _loadResults(e['id']?.toString() ?? ''),
              )),
        ],
      );
    }
    final rows = (_selectedResults!['results'] as List?) ?? [];
    final exam = _selectedResults!['exam'] as Map<String, dynamic>?;
    final title = exam?['title']?.toString() ?? 'Exam Results';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title,
            style: TextStyle(
                color: context.textColor,
                fontSize: 17,
                fontWeight: FontWeight.bold)),
        Text('${rows.length} submission(s)',
            style: TextStyle(color: context.greyColor, fontSize: 12)),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Text('No students have submitted yet.',
              style: TextStyle(color: context.greyColor))
        else
          ...rows.map((r) {
            if (r is! Map) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(r['student_name']?.toString() ?? 'Student',
                        style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text('${r['percentage'] ?? r['score'] ?? 0}%',
                      style: TextStyle(
                          color: context.accentColor,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
      ],
    );
  }
}
