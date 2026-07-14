import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/cbt_offline_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'cbt_exam_screen.dart';
import 'cbt_sessions_screen.dart';

/// CBT hub: pick subject → filter by year → download pack → take offline.
class CbtScreen extends StatefulWidget {
  const CbtScreen({super.key});

  @override
  State<CbtScreen> createState() => _CbtScreenState();
}

class _CbtScreenState extends State<CbtScreen> {
  final _api = ApiService();
  final _store = CbtOfflineStore.instance;

  String _examBoard = '';
  List<dynamic> _allExams = [];
  List<dynamic> _jambExams = [];
  List<dynamic> _ssceExams = [];
  List<String> _boards = [];
  String _activeTab = 'JAMB'; // JAMB | WAEC_NECO | JUNIOR_WAEC
  Set<String> _downloaded = {};
  bool _loadingExams = true;
  String? _busyExamId;
  String? _selectedSubject;
  String? _selectedYear;

  static final _yearRe = RegExp(r'(20\d{2}|19\d{2})');

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
      final jamb = (data['jamb_exams'] as List?) ?? [];
      final ssce = (data['ssce_exams'] as List?) ?? [];
      final boards = ((data['boards'] as List?) ?? [])
          .map((e) => e.toString())
          .toList();
      final ids = await _store.downloadedIds();
      if (mounted) {
        setState(() {
          _allExams = practice;
          _jambExams = jamb;
          _ssceExams = ssce;
          _boards = boards;
          if (boards.contains('JAMB')) {
            _activeTab = 'JAMB';
          } else if (boards.contains('JUNIOR_WAEC')) {
            _activeTab = 'JUNIOR_WAEC';
          } else if (boards.isNotEmpty) {
            _activeTab = boards.first;
          }
          _examBoard = data['exam_type']?.toString() ?? '';
          _downloaded = ids;
          _loadingExams = false;
          _selectedSubject = null;
          _selectedYear = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _allExams = [];
          _loadingExams = false;
        });
        if (e.message.toLowerCase().contains('setup')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Complete exam setup in your profile first.')),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingExams = false);
    }
  }

  String _examSubject(Map e) =>
      (e['subject']?.toString() ?? e['title']?.toString() ?? '').trim();

  String? _examYear(Map e) {
    final explicit = e['year']?.toString() ?? e['exam_year']?.toString();
    if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();
    final blob = '${e['title'] ?? ''} ${e['description'] ?? ''}';
    return _yearRe.firstMatch(blob)?.group(1);
  }

  List<dynamic> get _tabExams {
    if (_activeTab == 'JAMB') {
      return _jambExams.isNotEmpty ? _jambExams : _allExams;
    }
    if (_activeTab == 'JUNIOR_WAEC' || _activeTab == 'WAEC_NECO') {
      return _ssceExams.isNotEmpty ? _ssceExams : _allExams;
    }
    return _allExams;
  }

  String get _tabLabel {
    if (_activeTab == 'JAMB') return 'JAMB';
    if (_activeTab == 'JUNIOR_WAEC') return 'Junior WAEC';
    return 'WAEC / NECO';
  }

  List<String> get _subjects {
    final set = <String>{};
    for (final raw in _tabExams) {
      if (raw is! Map) continue;
      final s = _examSubject(Map<String, dynamic>.from(raw));
      if (s.isNotEmpty) set.add(s);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _yearsForSubject {
    final set = <String>{};
    final subject = (_selectedSubject ?? '').toLowerCase();
    for (final raw in _tabExams) {
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(raw);
      if (subject.isNotEmpty &&
          _examSubject(e).toLowerCase() != subject) {
        continue;
      }
      final y = _examYear(e);
      if (y != null) set.add(y);
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<Map<String, dynamic>> get _filteredExams {
    final subject = (_selectedSubject ?? '').toLowerCase();
    final list = _tabExams
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) {
          if (subject.isNotEmpty &&
              _examSubject(e).toLowerCase() != subject) {
            return false;
          }
          if (_selectedYear != null && _selectedYear!.isNotEmpty) {
            final y = _examYear(e);
            if (y != _selectedYear) return false;
          }
          return true;
        })
        .toList();
    list.sort((a, b) {
      final sa = _examSubject(a).toLowerCase();
      final sb = _examSubject(b).toLowerCase();
      final c = sa.compareTo(sb);
      if (c != 0) return c;
      final ya = _examYear(a) ?? '';
      final yb = _examYear(b) ?? '';
      return yb.compareTo(ya);
    });
    return list;
  }

  Future<void> _downloadExam(String examId) async {
    if (_busyExamId != null) return;
    setState(() => _busyExamId = examId);
    try {
      final pack = await _api.cbtDownloadExamRaw(examId);
      await _store.savePack(examId, pack);
      final ids = await _store.downloadedIds();
      if (!mounted) return;
      setState(() => _downloaded = ids);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Downloaded — you can start offline now.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busyExamId = null);
    }
  }

  Future<void> _startExam(BuildContext ctx, String examId, String title,
      {int? totalQ, int? durMins}) async {
    if (_busyExamId != null) return;
    setState(() => _busyExamId = examId);
    try {
      var pack = await _store.loadPack(examId);
      if (pack == null) {
        pack = await _api.cbtDownloadExamRaw(examId);
        await _store.savePack(examId, pack);
        if (mounted) {
          setState(() => _downloaded = {..._downloaded, examId});
        }
      }

      final rawQs = (pack['questions'] as List?) ?? [];
      final questions = rawQs.whereType<Map>().map((q) {
        final map = Map<String, dynamic>.from(q);
        final img = map['image_url']?.toString() ??
            map['diagram_url']?.toString() ??
            map['image']?.toString();
        if (img != null && img.isNotEmpty) {
          map['image_url'] = _api.resolveMediaUrl(img);
        }
        return CbtQuestion.fromJson(map);
      }).toList();

      // Rewrite absolute diagram URLs into the cached pack for true offline use.
      final resolvedQs = rawQs.whereType<Map>().map((q) {
        final map = Map<String, dynamic>.from(q);
        final img = map['image_url']?.toString() ??
            map['diagram_url']?.toString() ??
            map['image']?.toString();
        if (img != null && img.isNotEmpty) {
          map['image_url'] = _api.resolveMediaUrl(img);
        }
        return map;
      }).toList();
      pack = Map<String, dynamic>.from(pack)..['questions'] = resolvedQs;
      await _store.savePack(examId, pack);

      // Start online session when possible so scores still sync; offline pack still drives UI.
      CbtSession? session;
      try {
        session = await _api.cbtStartSession(examId);
      } catch (_) {
        session = null;
      }

      if (!ctx.mounted) return;
      final duration = session?.durationMinutes ??
          (pack['duration_minutes'] as num?)?.toInt() ??
          durMins ??
          60;
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => CbtExamScreen(
            subject: title,
            totalQuestions:
                questions.isNotEmpty ? questions.length : (totalQ ?? 0),
            durationSeconds: duration * 60,
            sessionId: session?.sessionId,
            questions: questions,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busyExamId = null);
    }
  }

  String get _boardLabel => _tabLabel;

  @override
  Widget build(BuildContext context) {
    final exams = _filteredExams;
    final subjects = _subjects;
    final years = _yearsForSubject;

    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: RefreshIndicator(
                color: context.accentColor,
                onRefresh: _loadExams,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_boards.length > 1 ||
                          (_boards.contains('JAMB') &&
                              _boards.any((b) =>
                                  b == 'WAEC_NECO' || b == 'JUNIOR_WAEC'))) ...[
                        Row(
                          children: [
                            if (_boards.contains('JAMB'))
                              Expanded(
                                child: _boardTab(
                                  context,
                                  'JAMB',
                                  'JAMB',
                                ),
                              ),
                            if (_boards.contains('JAMB') &&
                                (_boards.contains('WAEC_NECO') ||
                                    _boards.contains('JUNIOR_WAEC')))
                              const SizedBox(width: 10),
                            if (_boards.contains('WAEC_NECO'))
                              Expanded(
                                child: _boardTab(
                                  context,
                                  'WAEC / NECO',
                                  'WAEC_NECO',
                                ),
                              ),
                            if (_boards.contains('JUNIOR_WAEC'))
                              Expanded(
                                child: _boardTab(
                                  context,
                                  'Junior WAEC',
                                  'JUNIOR_WAEC',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                      Text(
                        '1. Choose the subject you are going for',
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loadingExams)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: CircularProgressIndicator(
                                color: context.accentColor),
                          ),
                        )
                      else if (subjects.isEmpty)
                        _emptyBox(context)
                      else ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _subjectChip(context, 'All', null),
                            ...subjects.map(
                                (s) => _subjectChip(context, s, s)),
                          ],
                        ),
                        if (years.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            '2. Pick the year (optional)',
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 36,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _yearChip(context, 'All', null),
                                ...years.map(
                                    (y) => _yearChip(context, y, y)),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          '3. Download, then start offline',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedSubject == null
                              ? 'Showing all $_boardLabel CBTs. Download a pack, then start anytime — including offline.'
                              : 'Download $_boardLabel questions for $_selectedSubject first. After that you can start even without internet.',
                          style: TextStyle(
                              color: context.greyColor, fontSize: 12, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        if (exams.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                _selectedSubject == null
                                    ? 'No $_boardLabel exams yet. Admin will upload them.'
                                    : 'No $_boardLabel exams for this subject yet. Admin will upload them.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: context.greyColor, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          ...exams.map((exam) {
                            final id = exam['id']?.toString() ?? '';
                            final title =
                                exam['title']?.toString() ?? 'Exam';
                            final desc =
                                exam['description']?.toString() ?? '';
                            final type =
                                exam['exam_type']?.toString() ?? _boardLabel;
                            final dur =
                                (exam['duration_minutes'] as num?)?.toInt();
                            final totalQ =
                                (exam['total_questions'] as num?)?.toInt();
                            final year = _examYear(exam);
                            final downloaded = _downloaded.contains(id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _ExamCard(
                                title: title,
                                description: desc,
                                examType: year != null ? '$type · $year' : type,
                                durationMins: dur,
                                totalQuestions: totalQ,
                                isBusy: _busyExamId == id,
                                isDownloaded: downloaded,
                                onDownload: () => _downloadExam(id),
                                onStart: () => _startExam(
                                  context,
                                  id,
                                  title,
                                  totalQ: totalQ,
                                  durMins: dur,
                                ),
                              ),
                            );
                          }),
                      ],
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardTab(BuildContext context, String label, String value) {
    final sel = _activeTab == value;
    return GestureDetector(
      onTap: () => setState(() {
        _activeTab = value;
        _selectedSubject = null;
        _selectedYear = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? context.accentColor : context.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? context.accentColor : context.borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel
                ? (context.isDark ? AppColors.background : Colors.white)
                : context.textColor,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _subjectChip(BuildContext context, String label, String? value) {
    final sel = _selectedSubject == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sel) ...[
            Icon(Icons.check, size: 16, color: context.accentColor),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selected: sel,
      onSelected: (_) => setState(() {
        _selectedSubject = value;
        _selectedYear = null;
      }),
      selectedColor: context.accentColor.withOpacity(0.2),
      labelStyle: TextStyle(
        color: sel ? context.accentColor : context.textColor,
        fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
          color: sel ? context.accentColor : context.borderColor),
      backgroundColor: context.cardColor,
    );
  }

  Widget _yearChip(BuildContext context, String label, String? value) {
    final sel = _selectedYear == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedYear = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? context.accentColor : context.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: sel ? context.accentColor : context.borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: sel
                  ? (context.isDark ? AppColors.background : Colors.white)
                  : context.greyColor,
              fontSize: 13,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyBox(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(children: [
          Icon(Icons.inbox_outlined, color: context.greyColor, size: 48),
          const SizedBox(height: 12),
          Text('No CBT exams available',
              style: TextStyle(
                  color: context.textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Admin will upload $_boardLabel packs for your subjects.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.greyColor, fontSize: 13),
          ),
        ]),
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
                Text('$_boardLabel · download then use offline',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.88), fontSize: 13)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CbtSessionsScreen())),
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
}

class _ExamCard extends StatelessWidget {
  final String title, description, examType;
  final int? durationMins, totalQuestions;
  final bool isBusy;
  final bool isDownloaded;
  final VoidCallback onDownload;
  final VoidCallback onStart;

  const _ExamCard({
    required this.title,
    required this.description,
    required this.examType,
    this.durationMins,
    this.totalQuestions,
    required this.isBusy,
    required this.isDownloaded,
    required this.onDownload,
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.menu_book_outlined,
                  color: context.accentColor, size: 24),
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
                  if (isDownloaded)
                    Text('Downloaded · ready offline',
                        style: TextStyle(
                            color: Colors.green.shade400,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
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
          ]),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy ? null : onDownload,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.accentColor,
                    side: BorderSide(color: context.accentColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    minimumSize: const Size(0, 42),
                  ),
                  child: isBusy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: context.accentColor))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isDownloaded
                                  ? Icons.download_done_rounded
                                  : Icons.download_rounded,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                isDownloaded ? 'Saved' : 'Download',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isBusy ? null : onStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor:
                        context.isDark ? AppColors.background : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    minimumSize: const Size(0, 42),
                  ),
                  child: Text(
                    isDownloaded ? 'Start offline' : 'Start',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
