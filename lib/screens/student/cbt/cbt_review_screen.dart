import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';

class CbtReviewScreen extends StatefulWidget {
  final String sessionId;
  const CbtReviewScreen({super.key, required this.sessionId});

  @override
  State<CbtReviewScreen> createState() => _CbtReviewScreenState();
}

class _CbtReviewScreenState extends State<CbtReviewScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _review;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.cbtSessionReview(widget.sessionId);
      if (mounted) setState(() { _review = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: AppColors.white,
        title: Text('Answer Review',
            style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.borderColor),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.yellow))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: context.greyColor, size: 48),
          SizedBox(height: 12),
          Text(_error ?? '', textAlign: TextAlign.center,
              style: TextStyle(color: context.greyColor, fontSize: 13)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellow, foregroundColor: Colors.black),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final questions = _review?['questions'] as List<dynamic>? ?? [];
    if (questions.isEmpty) {
      return Center(
        child: Text('No review data available',
            style: TextStyle(color: context.greyColor)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final q = questions[i] as Map<String, dynamic>;
        final questionText = q['question'] as String? ?? '';
        final options = (q['options'] as List<dynamic>?)
                ?.cast<String>() ?? [];
        final correctAnswer = q['correct_answer'] as String? ?? '';
        final studentAnswer = q['student_answer'] as String? ?? '';
        final explanation = q['explanation'] as String? ?? '';
        final isCorrect = studentAnswer == correctAnswer;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCorrect
                  ? const Color(0xFF4ADE80).withOpacity(0.4)
                  : const Color(0xFFFF6B6B).withOpacity(0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? const Color(0xFF4ADE80).withOpacity(0.15)
                          : const Color(0xFFFF6B6B).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCorrect ? Icons.check : Icons.close,
                      size: 16,
                      color: isCorrect
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFFF6B6B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Q${i + 1}',
                      style: TextStyle(
                          color: context.greyLColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),
              Text(questionText,
                  style: TextStyle(
                      color: context.textColor, fontSize: 14, height: 1.5)),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final isCorrectOpt = opt == correctAnswer;
                final isStudentOpt = opt == studentAnswer;
                Color optColor = AppColors.grey;
                Color bgColor = AppColors.surfaceLight;
                if (isCorrectOpt) {
                  optColor = const Color(0xFF4ADE80);
                  bgColor = const Color(0xFF4ADE80).withOpacity(0.1);
                } else if (isStudentOpt && !isCorrectOpt) {
                  optColor = const Color(0xFFFF6B6B);
                  bgColor = const Color(0xFFFF6B6B).withOpacity(0.1);
                }
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(opt,
                            style: TextStyle(color: optColor, fontSize: 13)),
                      ),
                      if (isCorrectOpt)
                        const Icon(Icons.check_circle_outline,
                            color: Color(0xFF4ADE80), size: 16),
                      if (isStudentOpt && !isCorrectOpt)
                        const Icon(Icons.cancel_outlined,
                            color: Color(0xFFFF6B6B), size: 16),
                    ],
                  ),
                );
              }),
              if (explanation.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.yellow.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.yellow.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: AppColors.yellow, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(explanation,
                            style: TextStyle(
                                color: context.greyLColor,
                                fontSize: 13,
                                height: 1.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
