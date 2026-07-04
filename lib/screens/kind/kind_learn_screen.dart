import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/student_ui.dart';
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
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Text(
                    'Learn & Play',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            KindHeroHeader(
              greeting: 'Learn & Play',
              subtitle:
                  'Pick a topic and get a mini-lesson or fun quiz from Sia.',
              icon: Icons.menu_book_rounded,
            ),
            const StudentSectionTitle(title: 'Choose a topic'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subject',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: context.cardColor,
                      borderRadius: BorderRadius.circular(16),
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
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _subject = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Topic',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _topicCtrl,
                    style: TextStyle(color: context.textColor),
                    decoration: InputDecoration(
                      hintText: 'e.g. Adding numbers, Animals, Colors...',
                      hintStyle: TextStyle(color: context.greyLColor),
                      filled: true,
                      fillColor: context.cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                            color: context.accentColor, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          context,
                          icon: Icons.menu_book_rounded,
                          label: 'Lesson',
                          colors: const [
                            Color(0xFF10B981),
                            Color(0xFF34D399),
                          ],
                          onTap: _loading ? null : () => _run(quiz: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionButton(
                          context,
                          icon: Icons.quiz_rounded,
                          label: 'Quiz',
                          colors: const [
                            Color(0xFFF59E0B),
                            Color(0xFFFBBF24),
                          ],
                          onTap: _loading ? null : () => _run(quiz: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 32),
              Center(
                child: CircularProgressIndicator(color: context.accentColor),
              ),
            ],
            if (_result != null) ...[
              const StudentSectionTitle(title: 'Result'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: context.isDark
                          ? [
                              const Color(0xFF1A1428),
                              const Color(0xFF221A35),
                            ]
                          : [Colors.white, const Color(0xFFF3EEFF)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: context.accentColor.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    _result!,
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required List<Color> colors,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colors.last.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
