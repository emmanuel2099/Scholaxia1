import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../student/cbt/cbt_exam_screen.dart';
import '../student/cbt/cbt_packages_screen.dart';

/// Primary 6 Common Entrance CBT for the Kids app.
/// Exams are created/published from the admin panel (exam type COMMON_ENTRANCE).
class KindCbtScreen extends StatefulWidget {
  const KindCbtScreen({super.key});

  @override
  State<KindCbtScreen> createState() => _KindCbtScreenState();
}

class _KindCbtScreenState extends State<KindCbtScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<dynamic> _exams = [];
  String? _startingExamId;
  String? _error;

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
      final data = await _api.cbtExams(examType: 'COMMON_ENTRANCE');
      if (!mounted) return;
      setState(() {
        _exams = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _exams = [];
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load Common Entrance exams.';
      });
    }
  }

  Future<void> _startExam(Map<String, dynamic> exam) async {
    final examId = exam['id']?.toString() ?? '';
    final title = exam['title']?.toString() ?? 'Common Entrance';
    if (examId.isEmpty || _startingExamId != null) return;
    setState(() => _startingExamId = examId);
    try {
      final session = await _api.cbtStartSession(examId);
      final questions = await _api.cbtDownloadExam(examId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CbtExamScreen(
            subject: title,
            totalQuestions: questions.isNotEmpty
                ? questions.length
                : session.totalQuestions,
            durationSeconds: session.durationMinutes * 60,
            sessionId: session.sessionId,
            questions: questions,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _startingExamId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: context.textColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Common Entrance CBT',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Annual package',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CbtPackagesScreen(kidsOnly: true),
                      ),
                    ),
                    icon: Icon(
                      Icons.workspace_premium_rounded,
                      color: context.accentColor,
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: context.accentColor,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Primary 6 practice exams — added by admin. Take each subject to prepare for Common Entrance.',
                style: TextStyle(
                  color: context.greyColor,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.accentColor,
                      ),
                    )
                  : RefreshIndicator(
                      color: context.accentColor,
                      onRefresh: _load,
                      child: _exams.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 80),
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 48,
                                  color: context.greyColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _error ?? 'No Common Entrance exams yet',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.textColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ask admin to add exams with type COMMON_ENTRANCE.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.greyColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                              itemCount: _exams.length,
                              itemBuilder: (context, i) {
                                final exam = Map<String, dynamic>.from(
                                  _exams[i] as Map,
                                );
                                final id = exam['id']?.toString() ?? '';
                                final title =
                                    exam['title']?.toString() ?? 'Exam';
                                final subject =
                                    exam['subject']?.toString() ?? '';
                                final dur = exam['duration_minutes'] as int?;
                                final totalQ = exam['total_questions'] as int?;
                                final starting = _startingExamId == id;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Material(
                                    color: context.isDark
                                        ? const Color(0xFF1A1428)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: starting
                                          ? null
                                          : () => _startExam(exam),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: context.accentColor
                                                .withOpacity(0.18),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFF0EA5E9),
                                                    Color(0xFF6366F1),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: starting
                                                  ? const Padding(
                                                      padding: EdgeInsets.all(
                                                        12,
                                                      ),
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.white,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.quiz_rounded,
                                                      color: Colors.white,
                                                    ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    title,
                                                    style: TextStyle(
                                                      color: context.textColor,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    [
                                                      if (subject.isNotEmpty)
                                                        subject,
                                                      if (totalQ != null)
                                                        '$totalQ questions',
                                                      if (dur != null)
                                                        '$dur min',
                                                    ].join(' · '),
                                                    style: TextStyle(
                                                      color: context.greyColor,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.play_circle_fill_rounded,
                                              color: context.accentColor,
                                              size: 28,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
