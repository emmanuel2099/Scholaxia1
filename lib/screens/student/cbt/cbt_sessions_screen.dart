import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'cbt_result_screen.dart';

class CbtSessionsScreen extends StatefulWidget {
  const CbtSessionsScreen({super.key});

  @override
  State<CbtSessionsScreen> createState() => _CbtSessionsScreenState();
}

class _CbtSessionsScreenState extends State<CbtSessionsScreen> {
  final _api = ApiService();
  List<dynamic> _sessions = [];
  bool _loading = true;
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
      final data = await _api.cbtMySessions();
      if (mounted) setState(() {
        _sessions = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _sessions = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: context.accentColor))
                  : _error != null
                      ? _buildError(context)
                      : _sessions.isEmpty
                          ? _buildEmpty(context)
                          : _buildList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
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
                const Text(
                  'My CBT Sessions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Review your past mock exam results',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: const Icon(Icons.history_rounded, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: context.greyColor, size: 48),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.greyColor, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.accentColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.quiz_outlined, color: context.accentColor, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'No sessions yet',
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Take a CBT exam to see your history here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.greyColor, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return RefreshIndicator(
      color: context.accentColor,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final s = _sessions[i] as Map<String, dynamic>;
          final sessionId = s['session_id'] as String? ?? s['id'] as String? ?? '';
          final examTitle =
              s['exam_title'] as String? ?? s['subject'] as String? ?? 'Exam';
          final score = s['score'];
          final percentage = (s['percentage'] as num?)?.toDouble();
          final submittedAt =
              s['submitted_at'] as String? ?? s['created_at'] as String? ?? '';
          final status = s['status'] as String? ?? 'completed';

          final isCompleted = status == 'completed' || status == 'submitted';
          final pct = percentage ?? 0.0;
          final scoreColor = pct >= 70
              ? const Color(0xFF22C55E)
              : pct >= 50
                  ? context.accentColor
                  : const Color(0xFFEF4444);

          return Material(
            color: context.cardColor,
            elevation: context.isDark ? 0 : 2,
            shadowColor: context.accentColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: isCompleted && sessionId.isNotEmpty
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CbtResultScreen(sessionId: sessionId),
                        ),
                      )
                  : null,
              borderRadius: BorderRadius.circular(18),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.borderColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: isCompleted ? (pct / 100).clamp(0.0, 1.0) : null,
                              strokeWidth: 4,
                              backgroundColor: scoreColor.withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation(scoreColor),
                            ),
                            if (isCompleted)
                              Text(
                                '${pct.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: scoreColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            else
                              Icon(Icons.hourglass_empty,
                                  color: context.greyColor, size: 22),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              examTitle,
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? const Color(0xFF22C55E).withOpacity(0.12)
                                        : context.surfColor,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isCompleted
                                          ? const Color(0xFF22C55E).withOpacity(0.3)
                                          : context.borderColor,
                                    ),
                                  ),
                                  child: Text(
                                    isCompleted ? 'Completed' : status,
                                    style: TextStyle(
                                      color: isCompleted
                                          ? const Color(0xFF22C55E)
                                          : context.greyColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (score != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    'Score: $score',
                                    style: TextStyle(
                                        color: context.greyColor, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                            if (submittedAt.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                _formatDate(submittedAt),
                                style: TextStyle(
                                    color: context.greyColor, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (isCompleted)
                        Icon(Icons.chevron_right_rounded,
                            color: context.accentColor, size: 24),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
