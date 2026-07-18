import 'package:flutter/material.dart';
import '../../api/api_service.dart';
import '../../theme/app_theme.dart';
import '../kind/kind_shell.dart';
import '../student/student_shell.dart';

/// Post-signup: class level + exams. SS students can select both JAMB and WAEC/NECO
/// with separate subject lists.
class ExamSubjectSetupScreen extends StatefulWidget {
  final bool popOnComplete;
  const ExamSubjectSetupScreen({super.key, this.popOnComplete = false});

  @override
  State<ExamSubjectSetupScreen> createState() => _ExamSubjectSetupScreenState();
}

class _ExamSubjectSetupScreenState extends State<ExamSubjectSetupScreen> {
  final _api = ApiService();

  String _educationLevel = 'SS3';
  bool _enableJamb = true;
  bool _enableSsce = true;
  String _ssceBoard = 'WAEC'; // WAEC | NECO
  final _jambSelected = <String>{};
  final _ssceSelected = <String>{};
  List<String> _availableSubjects = [];
  bool _loadingSubjects = true;
  bool _saving = false;

  bool get _isJss3 {
    final n = _educationLevel.toUpperCase().replaceAll(' ', '');
    return n == 'JSS3';
  }

  bool get _isCommonEntrance {
    final n = _educationLevel.toUpperCase().replaceAll(' ', '');
    return n == 'COMMONENTRANCE';
  }

  bool get _isPrimary6 {
    final n = _educationLevel.toUpperCase().replaceAll(' ', '');
    return n == 'PRIMARY6' || n == 'P6' || n == 'PRY6';
  }

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const StudentShell()),
        (_) => false,
      );
    }
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
            'Basic Science',
            'Basic Technology',
            'Social Studies',
          ];
          _loadingSubjects = false;
        });
      }
    }
  }

  void _selectLevel(String level) {
    setState(() {
      _educationLevel = level;
      if (_isJss3Level(level) || _isCommonEntranceLevel(level)) {
        _enableJamb = false;
        _enableSsce = true;
        _ssceBoard = _isCommonEntranceLevel(level) ? 'COMMON_ENTRANCE' : 'WAEC';
        _jambSelected.clear();
        if (_isCommonEntranceLevel(level)) _ssceSelected.clear();
      } else if (_isPrimary6Level(level)) {
        _enableJamb = false;
        _enableSsce = false;
      } else {
        // SS / JAMB prep — allow both by default
        if (!_enableJamb && !_enableSsce) {
          _enableJamb = true;
          _enableSsce = true;
        }
      }
    });
  }

  bool _isPrimary6Level(String level) {
    final n = level.toUpperCase().replaceAll(' ', '');
    return n == 'PRIMARY6' || n == 'P6' || n == 'PRY6';
  }

  bool _isJss3Level(String level) {
    final n = level.toUpperCase().replaceAll(' ', '');
    return n == 'JSS3';
  }

  bool _isCommonEntranceLevel(String level) {
    final n = level.toUpperCase().replaceAll(' ', '');
    return n == 'COMMONENTRANCE';
  }

  void _toggle(Set<String> selected, String subject, int limit, String label) {
    setState(() {
      if (selected.contains(subject)) {
        selected.remove(subject);
      } else if (selected.length < limit) {
        selected.add(subject);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: pick up to $limit subjects.')),
        );
      }
    });
  }

  Future<void> _continue() async {
    if (_isPrimary6) {
      setState(() => _saving = true);
      try {
        final data = await _api.setupExam(
          educationLevel: _educationLevel,
          examType: 'JAMB',
          subjects: const ['Mathematics'],
        );
        if (!mounted) return;
        if (data['redirect'] == 'kind' || data['role'] == 'kind') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const KindShell()),
            (_) => false,
          );
          return;
        }
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    if (_isCommonEntrance) {
      if (_ssceSelected.length != 9) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Common Entrance requires exactly 9 subjects.')),
        );
        return;
      }
      setState(() => _saving = true);
      try {
        await _api.setupExam(
          educationLevel: _educationLevel,
          enableJamb: false,
          enableSsce: true,
          ssceExamType: 'COMMON_ENTRANCE',
          ssceSubjects: _ssceSelected.toList(),
          examType: 'WAEC',
          subjects: _ssceSelected.toList(),
        );
        if (!mounted) return;
        _goNext();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    if (_isJss3) {
      if (_ssceSelected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one subject for Junior WAEC.')),
        );
        return;
      }
      setState(() => _saving = true);
      try {
        await _api.setupExam(
          educationLevel: _educationLevel,
          enableJamb: false,
          enableSsce: true,
          ssceExamType: 'WAEC',
          ssceSubjects: _ssceSelected.toList(),
          examType: 'JUNIOR_WAEC',
          subjects: _ssceSelected.toList(),
        );
        if (!mounted) return;
        _goNext();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    if (!_enableJamb && !_enableSsce) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn on JAMB and/or WAEC/NECO.')),
      );
      return;
    }
    if (_enableJamb && _jambSelected.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JAMB needs exactly 4 subjects.')),
      );
      return;
    }
    if (_enableSsce && _ssceSelected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one WAEC/NECO subject.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _api.setupExam(
        educationLevel: _educationLevel,
        enableJamb: _enableJamb,
        enableSsce: _enableSsce,
        jambSubjects: _jambSelected.toList(),
        ssceExamType: _ssceBoard,
        ssceSubjects: _ssceSelected.toList(),
      );
      if (!mounted) return;
      _goNext();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goNext() {
    if (widget.popOnComplete && Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const StudentShell()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final btnFg = context.isDark ? AppColors.background : Colors.white;
    final levels = const [
      'Primary 6',
      'Common Entrance',
      'JSS3',
      'SS1',
      'SS2',
      'SS3',
      'JAMB',
    ];

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _goBack,
          icon: Icon(Icons.arrow_back_rounded, color: context.textColor),
        ),
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
                    'Choose your class. SS students can select both JAMB and WAEC/NECO with separate subjects.',
                    style: TextStyle(
                        color: context.greyColor, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  _label(context, 'EDUCATION LEVEL'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: levels.map((level) {
                      final sel = _educationLevel == level;
                      return ChoiceChip(
                        label: Text(level),
                        selected: sel,
                        onSelected: (_) => _selectLevel(level),
                        selectedColor: context.accentColor.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: sel ? context.accentColor : context.textColor,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(
                            color: sel
                                ? context.accentColor
                                : context.borderColor),
                        backgroundColor: context.cardColor,
                      );
                    }).toList(),
                  ),
                  if (_isPrimary6) ...[
                    const SizedBox(height: 20),
                    _infoBox(
                      context,
                      'Primary 6 opens the Kids app. Common Entrance CBT is uploaded by admin there.',
                    ),
                  ],
                  if (_isCommonEntrance) ...[
                    const SizedBox(height: 24),
                    _infoBox(
                      context,
                      'Common Entrance CBT is taken one subject at a time. Pick exactly 9 subjects.',
                    ),
                    const SizedBox(height: 16),
                    _label(context, 'COMMON ENTRANCE SUBJECTS (${_ssceSelected.length}/9)'),
                    const SizedBox(height: 10),
                    _subjectWrap(
                      context,
                      selected: _ssceSelected,
                      limit: 9,
                      label: 'Common Entrance',
                    ),
                  ],
                  if (_isJss3) ...[
                    const SizedBox(height: 24),
                    _infoBox(
                      context,
                      'Junior WAEC (BECE) — take one subject at a time. Admin uploads those questions.',
                    ),
                    const SizedBox(height: 16),
                    _label(context, 'JUNIOR WAEC SUBJECTS'),
                    const SizedBox(height: 10),
                    _subjectWrap(
                      context,
                      selected: _ssceSelected,
                      limit: 9,
                      label: 'Junior WAEC',
                    ),
                  ],
                  if (!_isPrimary6 && !_isJss3 && !_isCommonEntrance) ...[
                    const SizedBox(height: 24),
                    _label(context, 'EXAM BOARDS (PICK ONE OR BOTH)'),
                    const SizedBox(height: 10),
                    _boardToggle(
                      context,
                      title: 'JAMB UTME',
                      subtitle: 'Exactly 4 subjects',
                      value: _enableJamb,
                      onChanged: (v) => setState(() => _enableJamb = v),
                    ),
                    const SizedBox(height: 10),
                    _boardToggle(
                      context,
                      title: 'WAEC / NECO',
                      subtitle: 'Up to 9 subjects',
                      value: _enableSsce,
                      onChanged: (v) => setState(() => _enableSsce = v),
                    ),
                    if (_enableSsce) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('WAEC'),
                            selected: _ssceBoard == 'WAEC',
                            onSelected: (_) =>
                                setState(() => _ssceBoard = 'WAEC'),
                            selectedColor:
                                context.accentColor.withOpacity(0.2),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('NECO'),
                            selected: _ssceBoard == 'NECO',
                            onSelected: (_) =>
                                setState(() => _ssceBoard = 'NECO'),
                            selectedColor:
                                context.accentColor.withOpacity(0.2),
                          ),
                        ],
                      ),
                    ],
                    if (_enableJamb) ...[
                      const SizedBox(height: 22),
                      _label(context,
                          'JAMB SUBJECTS (${_jambSelected.length}/4)'),
                      const SizedBox(height: 10),
                      _subjectWrap(
                        context,
                        selected: _jambSelected,
                        limit: 4,
                        label: 'JAMB',
                      ),
                    ],
                    if (_enableSsce) ...[
                      const SizedBox(height: 22),
                      _label(context,
                          '$_ssceBoard SUBJECTS (${_ssceSelected.length}/9)'),
                      const SizedBox(height: 10),
                      _subjectWrap(
                        context,
                        selected: _ssceSelected,
                        limit: 9,
                        label: _ssceBoard,
                      ),
                    ],
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accentColor,
                        foregroundColor: btnFg,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: btnFg),
                            )
                          : Text(
                              _isPrimary6 ? 'Continue to Kids app' : 'Save & continue',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          color: context.greyColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      );

  Widget _infoBox(BuildContext context, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.accentColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.accentColor.withOpacity(0.4)),
        ),
        child: Text(text,
            style:
                TextStyle(color: context.textColor, fontSize: 13, height: 1.4)),
      );

  Widget _boardToggle(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? context.accentColor.withOpacity(0.12)
            : context.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? context.accentColor : context.borderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: context.textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(subtitle,
                    style:
                        TextStyle(color: context.greyColor, fontSize: 12)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: context.accentColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _subjectWrap(
    BuildContext context, {
    required Set<String> selected,
    required int limit,
    required String label,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _availableSubjects.map((s) {
        final sel = selected.contains(s);
        return FilterChip(
          label: Text(s),
          selected: sel,
          onSelected: (_) => _toggle(selected, s, limit, label),
          selectedColor: context.accentColor.withOpacity(0.2),
          checkmarkColor: context.accentColor,
          labelStyle: TextStyle(
            color: sel ? context.accentColor : context.textColor,
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          side: BorderSide(
              color: sel ? context.accentColor : context.borderColor),
          backgroundColor: context.cardColor,
        );
      }).toList(),
    );
  }
}
