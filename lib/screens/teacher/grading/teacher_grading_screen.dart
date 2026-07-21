import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../teacher_shared.dart';
import '../../student/assignments/assignment_screen.dart';

class TeacherGradingScreen extends StatefulWidget {
  const TeacherGradingScreen({super.key});

  @override
  State<TeacherGradingScreen> createState() => _TeacherGradingScreenState();
}

class _TeacherGradingScreenState extends State<TeacherGradingScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _teacherName;
  int _unread = 0;
  List<_Submission> _submissions = [];

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
        _api.teacherPendingAssignments(),
      ]);
      final pending = results[2] as List;
      final subs = <_Submission>[];
      for (final raw in pending) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final studentId = m['student_id']?.toString() ?? '';
        String studentName = 'Student';
        if (studentId.isNotEmpty) {
          try {
            final p = await _api.getStudentProfileById(studentId);
            studentName = p.fullName;
          } catch (_) {}
        }
        subs.add(_Submission(
          id: m['id']?.toString() ?? '',
          studentName: studentName,
          caption: m['caption']?.toString() ?? 'Assignment submission',
          fileUrl: m['file_url']?.toString() ?? '',
          fileType: m['file_type']?.toString() ?? 'file',
          submittedAt: TeacherUtils.relativeTime(m['submitted_at']?.toString() ?? ''),
        ));
      }
      if (mounted) {
        setState(() {
          _teacherName = (results[0] as Map)['full_name']?.toString();
          _unread = results[1] as int;
          _submissions = subs;
          _loading = false;
        });
        teacherUnreadCount.value = results[1] as int;
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showGradeSheet(_Submission sub) {
    final scoreCtrl = TextEditingController();
    final feedbackCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.headerColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Grade ${sub.studentName}',
                style: TextStyle(
                    color: ctx.textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: scoreCtrl,
              style: TextStyle(color: ctx.textColor),
              decoration: InputDecoration(
                hintText: 'Score (e.g. 85/100 or B+)',
                hintStyle: TextStyle(color: ctx.greyColor),
                filled: true,
                fillColor: ctx.surfColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: feedbackCtrl,
              maxLines: 3,
              style: TextStyle(color: ctx.textColor),
              decoration: InputDecoration(
                hintText: 'Feedback for the student...',
                hintStyle: TextStyle(color: ctx.greyColor),
                filled: true,
                fillColor: ctx.surfColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final score = scoreCtrl.text.trim();
                  final feedback = feedbackCtrl.text.trim();
                  if (score.isEmpty && feedback.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    await _api.postAssignmentResult(
                      submissionId: sub.id,
                      resultText: feedback.isNotEmpty ? feedback : 'Graded',
                      resultScore: score.isNotEmpty ? score : null,
                      resultFeedback: feedback.isNotEmpty ? feedback : null,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Result posted to student.')),
                      );
                      _load();
                    }
                  } on ApiException catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ctx.accentColor,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Post Result',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSubmission(_Submission sub) {
    if (sub.fileUrl.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssignmentPdfScreen(
          url: sub.fileUrl,
          title: sub.caption,
        ),
      ),
    );
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
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Grading',
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Review and grade student assignment submissions.',
                      style: TextStyle(color: context.greyColor, fontSize: 13)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryChip(
                          value: '${_submissions.length}',
                          label: 'Pending',
                          color: const Color(0xFFFF6B6B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: accent))
                  : RefreshIndicator(
                      color: accent,
                      onRefresh: _load,
                      child: _submissions.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 80),
                                Center(
                                  child: Text('No pending submissions.',
                                      style: TextStyle(color: context.greyColor)),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                              itemCount: _submissions.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _SubmissionCard(
                                submission: _submissions[i],
                                onOpen: () => _openSubmission(_submissions[i]),
                                onGrade: () => _showGradeSheet(_submissions[i]),
                              ),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Submission {
  final String id;
  final String studentName;
  final String caption;
  final String fileUrl;
  final String fileType;
  final String submittedAt;
  const _Submission({
    required this.id,
    required this.studentName,
    required this.caption,
    required this.fileUrl,
    required this.fileType,
    required this.submittedAt,
  });
}

class _SummaryChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _SummaryChip(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: context.greyColor, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final _Submission submission;
  final VoidCallback onGrade;
  final VoidCallback onOpen;
  const _SubmissionCard({
    required this.submission,
    required this.onOpen,
    required this.onGrade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: context.accentColor.withOpacity(0.15),
            child: Text(
              submission.studentName.isNotEmpty
                  ? submission.studentName[0].toUpperCase()
                  : 'S',
              style: TextStyle(
                  color: context.accentColor, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(submission.studentName,
                    style: TextStyle(
                        color: context.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(submission.caption,
                    style: TextStyle(color: context.greyColor, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('${submission.fileType} · ${submission.submittedAt}',
                    style: TextStyle(color: context.greyColor, fontSize: 11)),
              ],
            ),
          ),
          Column(
            children: [
              TextButton(
                onPressed: onOpen,
                child: const Text('Open PDF'),
              ),
              ElevatedButton(
                onPressed: onGrade,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text('Grade', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
