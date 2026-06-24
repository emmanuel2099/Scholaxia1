import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import 'cbt_result_screen.dart';

const _green = Color(0xFF22C55E);
const _textDark = Color(0xFF111827);
const _textGrey = Color(0xFF6B7280);
const _bg = Color(0xFFF9FAFB);
const _border = Color(0xFFE5E7EB);

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
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.cbtMySessions();
      if (mounted) setState(() { _sessions = data; _loading = false; });
    } catch (_) {
      // 404 or any error — just show empty state, not an error
      if (mounted) setState(() { _sessions = []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _textDark,
        title: const Text('My CBT Sessions',
            style: TextStyle(color: _textDark, fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _error != null
              ? _buildError()
              : _sessions.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: _textGrey, size: 48),
          SizedBox(height: 12),
          Text(_error ?? '', textAlign: TextAlign.center,
              style: TextStyle(color: _textGrey, fontSize: 13)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.black),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.quiz_outlined, color: _textGrey, size: 56),
          SizedBox(height: 12),
          Text('No sessions yet',
              style: TextStyle(
                  color: _textDark, fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text("Take a CBT exam to see your history here.",
              style: TextStyle(color: _textGrey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      color: _green,
      backgroundColor: Colors.white,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final s = _sessions[i] as Map<String, dynamic>;
          final sessionId = s['session_id'] as String? ?? s['id'] as String? ?? '';
          final examTitle = s['exam_title'] as String? ?? s['subject'] as String? ?? 'Exam';
          final score = s['score'];
          final percentage = (s['percentage'] as num?)?.toDouble();
          final submittedAt = s['submitted_at'] as String? ?? s['created_at'] as String? ?? '';
          final status = s['status'] as String? ?? 'completed';

          final isCompleted = status == 'completed' || status == 'submitted';
          final pct = percentage ?? 0.0;
          final scoreColor = pct >= 70
              ? const Color(0xFF4ADE80)
              : pct >= 50
                  ? _green
                  : const Color(0xFFFF6B6B);

          return GestureDetector(
            onTap: isCompleted && sessionId.isNotEmpty
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CbtResultScreen(sessionId: sessionId)))
                : null,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? scoreColor.withOpacity(0.12)
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: isCompleted
                        ? Center(
                            child: Text(
                              '${pct.toStringAsFixed(0)}%',
                              style: TextStyle(
                                  color: scoreColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                          )
                        : Icon(Icons.hourglass_empty,
                            color: _textGrey, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(examTitle,
                            style: TextStyle(
                                color: _textDark,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? const Color(0xFF4ADE80).withOpacity(0.1)
                                    : const Color(0xFFE5E7EB),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isCompleted ? 'Completed' : status,
                                style: TextStyle(
                                    color: isCompleted
                                        ? const Color(0xFF4ADE80)
                                        : _textGrey,
                                    fontSize: 11),
                              ),
                            ),
                            if (score != null) ...[
                              const SizedBox(width: 8),
                              Text('Score: $score',
                                  style: TextStyle(
                                      color: _textGrey, fontSize: 12)),
                            ],
                          ],
                        ),
                        if (submittedAt.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(_formatDate(submittedAt),
                              style: TextStyle(
                                  color: _textGrey, fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                  if (isCompleted)
                    Icon(Icons.chevron_right, color: _textGrey, size: 20),
                ],
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
