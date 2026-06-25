import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import 'kind_shared.dart';

class KindLearnScreen extends StatefulWidget {
  const KindLearnScreen({super.key});

  @override
  State<KindLearnScreen> createState() => _KindLearnScreenState();
}

class _KindLearnScreenState extends State<KindLearnScreen> {
  final _api = ApiService();
  final _topicCtrl = TextEditingController();
  String _subject = 'General';
  String? _result;
  bool _loading = false;
  List<String> _subjects = ['General'];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final subs = await _api.kindSubjects();
      if (mounted && subs.isNotEmpty) setState(() => _subjects = subs);
    } catch (_) {}
  }

  Future<void> _run({required bool quiz}) async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final text = quiz
          ? await _api.kindSiaQuiz(topic: topic, subject: _subject)
          : await _api.kindSiaLearn(topic: topic, subject: _subject);
      if (mounted) setState(() => _result = text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _result = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            Text('Learn & Play',
                style: TextStyle(
                    color: context.textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Pick a topic and get a mini-lesson or fun quiz.',
                style: TextStyle(color: context.greyColor, fontSize: 13)),
            const SizedBox(height: 20),
            Text('Subject',
                style: TextStyle(
                    color: context.textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.surfColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _subjects.contains(_subject)
                      ? _subject
                      : _subjects.first,
                  isExpanded: true,
                  dropdownColor: context.cardColor,
                  style: TextStyle(color: context.textColor),
                  items: _subjects
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _subject = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Topic',
                style: TextStyle(
                    color: context.textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _topicCtrl,
              style: TextStyle(color: context.textColor),
              decoration: InputDecoration(
                hintText: 'e.g. Adding numbers, Animals, Colors...',
                hintStyle: TextStyle(color: context.greyLColor),
                filled: true,
                fillColor: context.surfColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : () => _run(quiz: false),
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: const Text('Lesson'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KidColors.learn,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : () => _run(quiz: true),
                    icon: const Icon(Icons.quiz_outlined, size: 18),
                    label: const Text('Quiz'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KidColors.quiz,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 24),
              Center(
                  child: CircularProgressIndicator(color: KidColors.accent)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(_result!,
                    style: TextStyle(
                        color: context.textColor,
                        fontSize: 14,
                        height: 1.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
