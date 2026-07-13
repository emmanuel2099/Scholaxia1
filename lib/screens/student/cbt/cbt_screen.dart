import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'cbt_exam_screen.dart';
import 'cbt_sessions_screen.dart';

class CbtScreen extends StatefulWidget {
  const CbtScreen({super.key});

  @override
  State<CbtScreen> createState() => _CbtScreenState();
}

class _CbtScreenState extends State<CbtScreen> {
  String _selectedType = 'JAMB';
  final _types = ['JAMB', 'WAEC/NECO'];
  final _api = ApiService();
  bool _loadingExams = true;
  List<dynamic> _allExams = [];
  String? _startingExamId;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    setState(() => _loadingExams = true);
    try {
      final data = await _api.cbtExamsForMe();
      final practice = (data['practice_exams'] as List?) ?? [];
      final combined = [...practice];
      if (mounted) setState(() { _allExams = combined; _loadingExams = false; });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() { _allExams = []; _loadingExams = false; });
        if (e.message.toLowerCase().contains('setup')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Complete exam setup in your profile first.')),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() { _loadingExams = false; });
    }
  }

  Future<void> _startExam(BuildContext ctx, String examId, String title,
      {int? totalQ, int? durMins}) async {
    if (_startingExamId != null) return;
    setState(() => _startingExamId = examId);
    try {
      final session = await _api.cbtStartSession(examId);
      final questions = await _api.cbtDownloadExam(examId);
      if (!ctx.mounted) return;
      Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => CbtExamScreen(
          subject: title,
          totalQuestions: questions.isNotEmpty ? questions.length : session.totalQuestions,
          durationSeconds: session.durationMinutes * 60,
          sessionId: session.sessionId,
          questions: questions,
        ),
      ));
    } on ApiException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _startingExamId = null);
    }
  }

  List<dynamic> get _exams {
    final filter = _selectedType.toUpperCase();
    return _allExams.where((e) {
      final type =
          (e as Map<String, dynamic>)['exam_type']?.toString().toUpperCase() ??
              '';
      if (filter == 'JAMB') return type.contains('JAMB');
      if (filter == 'WAEC/NECO') {
        return type.contains('WAEC') || type.contains('NECO');
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final exams = _exams;
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTypeFilter(context),
                    const SizedBox(height: 20),
                    Text('AVAILABLE EXAMS',
                        style: TextStyle(
                            color: context.greyColor,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    if (_loadingExams)
                      Center(
                          child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: CircularProgressIndicator(color: context.accentColor),
                      ))
                    else if (exams.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Column(children: [
                            Icon(Icons.inbox_outlined, color: context.greyColor, size: 48),
                            const SizedBox(height: 12),
                            Text('No CBT exams available',
                                style: TextStyle(color: context.textColor, fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text('Check back later for available exams.',
                                style: TextStyle(color: context.greyColor, fontSize: 13)),
                          ]),
                        ),
                      )
                    else
                      ...exams.map((e) {
                        final exam = e as Map<String, dynamic>;
                        final id = exam['id'] as String? ?? '';
                        final title = exam['title'] as String? ?? 'Exam';
                        final desc = exam['description'] as String? ?? '';
                        final type = exam['exam_type'] as String? ?? '';
                        final dur = exam['duration_minutes'] as int?;
                        final totalQ = exam['total_questions'] as int?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ExamCard(
                            title: title,
                            description: desc,
                            examType: type,
                            durationMins: dur,
                            totalQuestions: totalQ,
                            isStarting: _startingExamId == id,
                            onStart: () => _startExam(context, id, title,
                                totalQ: totalQ, durMins: dur),
                          ),
                        );
                      }),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: AppGradients.hero(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const StudentBackButton(lightOnGradient: true),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CBT Practice',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                Text('JAMB & WAEC/NECO practice tests',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.88), fontSize: 13)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CbtSessionsScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.history_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('History',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilter(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = _types[i] == _selectedType;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedType = _types[i]);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: sel ? context.accentColor : context.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? context.accentColor : context.borderColor),
              ),
              alignment: Alignment.center,
              child: Text(_types[i],
                  style: TextStyle(
                      color: sel ? (context.isDark ? AppColors.background : Colors.white) : context.greyColor,
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
            ),
          );
        },
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  final String title, description, examType;
  final int? durationMins, totalQuestions;
  final bool isStarting;
  final VoidCallback onStart;

  const _ExamCard({
    required this.title,
    required this.description,
    required this.examType,
    this.durationMins,
    this.totalQuestions,
    required this.isStarting,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
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
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: context.accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.menu_book_outlined, color: context.accentColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  if (examType.isNotEmpty)
                    Text(examType,
                        style: TextStyle(
                            color: context.accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ]),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(description,
                style: TextStyle(
                    color: context.greyColor, fontSize: 13, height: 1.5)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (durationMins != null) ...[
              Icon(Icons.timer_outlined, color: context.greyColor, size: 14),
              const SizedBox(width: 4),
              Text('$durationMins Mins',
                  style: TextStyle(color: context.greyColor, fontSize: 12)),
              const SizedBox(width: 16),
            ],
            if (totalQuestions != null) ...[
              Icon(Icons.help_outline, color: context.greyColor, size: 14),
              const SizedBox(width: 4),
              Text('$totalQuestions Questions',
                  style: TextStyle(color: context.greyColor, fontSize: 12)),
            ],
            const Spacer(),
            SizedBox(
              height: 38,
              child: ElevatedButton(
                onPressed: isStarting ? null : onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: context.isDark ? AppColors.background : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  elevation: 0,
                ),
                child: isStarting
                    ? SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.isDark ? AppColors.background : Colors.white))
                    : const Text('Start →',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
