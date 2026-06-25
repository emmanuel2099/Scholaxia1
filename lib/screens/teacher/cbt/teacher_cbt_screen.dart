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

  void _showCreateExamSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.headerColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CreateExamSheet(api: _api, onCreated: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    return Scaffold(
      backgroundColor: context.bgColor,
      floatingActionButton: _selectedTab == 'My Exams'
          ? FloatingActionButton.extended(
              onPressed: _showCreateExamSheet,
              backgroundColor: accent,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text('New Exam',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
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
                      'Create school exams and review student scores.',
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
                                    color: sel ? Colors.black : context.greyLColor,
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
                  ? Center(
                      child: CircularProgressIndicator(color: accent))
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
              child: Text('No school exams yet. Tap New Exam to create one.',
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
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
                Text(subject,
                    style: TextStyle(color: color, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        color: context.greyColor, size: 14),
                    const SizedBox(width: 4),
                    Text('${e['duration_minutes'] ?? '—'} mins',
                        style: TextStyle(color: context.greyColor, fontSize: 12)),
                    const SizedBox(width: 12),
                    Icon(Icons.quiz_outlined,
                        color: context.greyColor, size: 14),
                    const SizedBox(width: 4),
                    Text('${e['total_questions'] ?? '—'} questions',
                        style: TextStyle(color: context.greyColor, fontSize: 12)),
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
      return Center(child: CircularProgressIndicator(color: context.accentColor));
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
                          color: context.accentColor, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _CreateExamSheet extends StatefulWidget {
  final ApiService api;
  final VoidCallback onCreated;
  const _CreateExamSheet({required this.api, required this.onCreated});

  @override
  State<_CreateExamSheet> createState() => _CreateExamSheetState();
}

class _CreateExamSheetState extends State<_CreateExamSheet> {
  final _titleCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _qCtrl = TextEditingController();
  final _aCtrl = TextEditingController(text: 'Option A');
  final _bCtrl = TextEditingController(text: 'Option B');
  final _cCtrl = TextEditingController(text: 'Option C');
  final _dCtrl = TextEditingController(text: 'Option D');
  int _duration = 30;
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    _qCtrl.dispose();
    _aCtrl.dispose();
    _bCtrl.dispose();
    _cCtrl.dispose();
    _dCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final subject = _subjectCtrl.text.trim();
    final question = _qCtrl.text.trim();
    if (title.isEmpty || subject.isEmpty || question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title, subject, and question are required.')),
      );
      return;
    }
    setState(() => _loading = true);
    final start = DateTime.now().toUtc();
    final end = start.add(const Duration(days: 7));
    try {
      await widget.api.createSchoolExam(
        title: title,
        subject: subject,
        durationMinutes: _duration,
        scheduledStart: start,
        scheduledEnd: end,
        cameraRequired: false,
        aiLocked: true,
        blockMinimize: true,
        questions: [
          {
            'question_text': question,
            'option_a': _aCtrl.text.trim(),
            'option_b': _bCtrl.text.trim(),
            'option_c': _cCtrl.text.trim(),
            'option_d': _dCtrl.text.trim(),
            'correct_option': 'A',
          },
        ],
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exam published! Students were notified.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Create School Exam',
                style: TextStyle(
                    color: context.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _field(_titleCtrl, 'Exam title'),
            const SizedBox(height: 10),
            _field(_subjectCtrl, 'Subject'),
            const SizedBox(height: 10),
            _field(_qCtrl, 'Sample question text'),
            const SizedBox(height: 10),
            _field(_aCtrl, 'Option A (correct)'),
            const SizedBox(height: 8),
            _field(_bCtrl, 'Option B'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: Colors.black,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Publish Exam',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: TextStyle(color: context.textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.greyColor),
        filled: true,
        fillColor: context.surfColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
