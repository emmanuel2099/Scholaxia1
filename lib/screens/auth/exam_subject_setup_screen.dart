import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../student/student_shell.dart';

/// Post-signup flow: pick exam type (JAMB / WAEC / NECO) and subjects, then go home.
class ExamSubjectSetupScreen extends StatefulWidget {
  final bool popOnComplete;
  const ExamSubjectSetupScreen({super.key, this.popOnComplete = false});

  @override
  State<ExamSubjectSetupScreen> createState() => _ExamSubjectSetupScreenState();
}

class _ExamSubjectSetupScreenState extends State<ExamSubjectSetupScreen> {
  final _api = ApiService();
  static const _examOptions = [
    ('JAMB', 'JAMB UTME', 'Pick exactly 4 subjects'),
    ('WAEC', 'WAEC WASSCE', 'Pick up to 9 subjects'),
    ('NECO', 'NECO SSCE', 'Pick up to 9 subjects'),
  ];

  String _examType = 'JAMB';
  String _educationLevel = 'SS3';
  final _selected = <String>{};
  List<String> _availableSubjects = [];
  bool _loadingSubjects = true;
  bool _saving = false;

  int get _subjectLimit => _examType == 'JAMB' ? 4 : 9;
  int get _subjectMinimum => _examType == 'JAMB' ? 4 : 1;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() => _loadingSubjects = true);
    try {
      final data = await _api.listAvailableSubjects();
      if (mounted) {
        setState(() {
          _availableSubjects = data;
          _loadingSubjects = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _availableSubjects = const [
            'Mathematics',
            'English Language',
            'Biology',
            'Chemistry',
            'Physics',
            'Economics',
            'Government',
            'Geography',
            'Literature',
            'Agricultural Science',
            'Commerce',
            'CRS',
            'IRS',
            'Further Mathematics',
            'Civic Education',
          ];
          _loadingSubjects = false;
        });
      }
    }
  }

  void _selectExam(String type) {
    setState(() {
      _examType = type;
      if (_selected.length > _subjectLimit) {
        _selected.removeAll(_selected.skip(_subjectLimit));
      }
    });
  }

  void _toggleSubject(String subject) {
    setState(() {
      if (_selected.contains(subject)) {
        _selected.remove(subject);
      } else if (_selected.length < _subjectLimit) {
        _selected.add(subject);
      } else if (_examType == 'JAMB') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JAMB requires exactly 4 subjects.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You can pick up to $_subjectLimit subjects.')),
        );
      }
    });
  }

  Future<void> _continue() async {
    if (_selected.length < _subjectMinimum) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _examType == 'JAMB'
                ? 'Select exactly 4 subjects for JAMB.'
                : 'Select at least one subject.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.setupExam(
        examType: _examType,
        subjects: _selected.toList(),
        educationLevel: _educationLevel,
      );
      if (!mounted) return;
      if (widget.popOnComplete && Navigator.canPop(context)) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const StudentShell()),
          (_) => false,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final btnFg = context.isDark ? AppColors.background : Colors.white;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Set up your exams',
          style: TextStyle(
            color: context.textColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loadingSubjects
          ? Center(child: CircularProgressIndicator(color: context.accentColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose your exam and subjects so we can personalize CBT, Sia, and your profile.',
                    style: TextStyle(color: context.greyColor, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'EXAM TYPE',
                    style: TextStyle(
                      color: context.greyColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._examOptions.map((opt) {
                    final selected = _examType == opt.$1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => _selectExam(opt.$1),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: selected
                                ? context.accentColor.withOpacity(0.12)
                                : context.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? context.accentColor : context.borderColor,
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: selected ? context.accentColor : context.greyColor,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opt.$2,
                                      style: TextStyle(
                                        color: context.textColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      opt.$3,
                                      style: TextStyle(color: context.greyColor, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  Text(
                    'EDUCATION LEVEL',
                    style: TextStyle(
                      color: context.greyColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['SS1', 'SS2', 'SS3', 'JAMB'].map((level) {
                      final sel = _educationLevel == level;
                      return ChoiceChip(
                        label: Text(level),
                        selected: sel,
                        onSelected: (_) => setState(() => _educationLevel = level),
                        selectedColor: context.accentColor.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: sel ? context.accentColor : context.textColor,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(color: sel ? context.accentColor : context.borderColor),
                        backgroundColor: context.cardColor,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SUBJECTS',
                        style: TextStyle(
                          color: context.greyColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        '${_selected.length}/$_subjectLimit',
                        style: TextStyle(
                          color: context.accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableSubjects.map((s) {
                      final sel = _selected.contains(s);
                      return FilterChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        onSelected: (_) => _toggleSubject(s),
                        selectedColor: context.accentColor.withOpacity(0.2),
                        checkmarkColor: context.accentColor,
                        labelStyle: TextStyle(
                          color: sel ? context.accentColor : context.textColor,
                        ),
                        side: BorderSide(color: sel ? context.accentColor : context.borderColor),
                        backgroundColor: context.cardColor,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accentColor,
                        foregroundColor: btnFg,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: btnFg),
                            )
                          : const Text(
                              'Continue to Home',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
