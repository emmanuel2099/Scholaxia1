import 'dart:math';
import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/cbt_offline_store.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/subject_match.dart';
import '../../../widgets/student_ui.dart';
import 'cbt_exam_screen.dart';
import 'cbt_sessions_screen.dart';

/// CBT hub: JAMB = all 4 subjects together; others = one subject at a time.
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
  String _activeTab = 'JAMB'; // JAMB | WAEC_NECO | JUNIOR_WAEC | COMMON_ENTRANCE
  List<String> _jambSubjects = [];
  List<String> _ssceSubjects = [];
  Set<String> _downloaded = {};
  bool _loadingExams = true;
  String? _busyExamId;
  String? _selectedSubject;

  static const _jambBundleId = '__jamb_bundle__';
  static final _yearRe = RegExp(r'(20\d{2}|19\d{2})');

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  Future<void> _loadExams() async {
    setState(() => _loadingExams = true);
    try {
      // Always load profile subjects for the WAEC/NECO slider.
      List<String> profileJamb = [];
      List<String> profileSsce = [];
      try {
        final profile = await _api.getStudentProfile();
        profileJamb = profile.jambSubjects;
        profileSsce = profile.ssceSubjects.isNotEmpty
            ? profile.ssceSubjects
            : profile.subjects;
      } catch (_) {}

      final data = await _api.cbtExamsForMe();
      final practice = (data['practice_exams'] as List?) ?? [];
      final jamb = (data['jamb_exams'] as List?) ?? [];
      final ssce = (data['ssce_exams'] as List?) ?? [];
      final boards = ((data['boards'] as List?) ?? [])
          .map((e) => e.toString())
          .toList();
      final ids = await _store.downloadedIds();

      final apiJamb = ((data['jamb_subjects'] as List?) ?? [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final apiSsce = ((data['ssce_subjects'] as List?) ?? [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();

      if (mounted) {
        setState(() {
          _allExams = practice;
          _jambExams = jamb;
          _ssceExams = ssce;
          _boards = boards;
          if (boards.contains('WAEC_NECO')) {
            _activeTab = 'WAEC_NECO';
          } else if (boards.contains('JAMB')) {
            _activeTab = 'JAMB';
          } else if (boards.contains('JUNIOR_WAEC')) {
            _activeTab = 'JUNIOR_WAEC';
          } else if (boards.contains('COMMON_ENTRANCE')) {
            _activeTab = 'COMMON_ENTRANCE';
          } else if (boards.isNotEmpty) {
            _activeTab = boards.first;
          }
          _examBoard = data['exam_type']?.toString() ?? '';
          _jambSubjects = apiJamb.isNotEmpty ? apiJamb : profileJamb;
          _ssceSubjects = apiSsce.isNotEmpty ? apiSsce : profileSsce;
          _downloaded = ids;
          _loadingExams = false;
          _selectedSubject = null;
          _ensureDefaultSubject();
        });
      }
    } on ApiException catch (e) {
      // Even if CBT exams fail, still try to show profile subjects.
      try {
        final profile = await _api.getStudentProfile();
        if (mounted) {
          setState(() {
            _jambSubjects = profile.jambSubjects;
            _ssceSubjects = profile.ssceSubjects.isNotEmpty
                ? profile.ssceSubjects
                : profile.subjects;
            _boards = [
              if (_jambSubjects.isNotEmpty) 'JAMB',
              if (_ssceSubjects.isNotEmpty) 'WAEC_NECO',
            ];
            if (_boards.contains('WAEC_NECO')) {
              _activeTab = 'WAEC_NECO';
            } else if (_boards.isNotEmpty) {
              _activeTab = _boards.first;
            }
            _loadingExams = false;
            _ensureDefaultSubject();
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _allExams = [];
            _loadingExams = false;
          });
        }
      }
      if (mounted && e.message.toLowerCase().contains('setup')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Complete exam setup in your profile first.')),
        );
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
    if (_activeTab == 'JUNIOR_WAEC' ||
        _activeTab == 'WAEC_NECO' ||
        _activeTab == 'COMMON_ENTRANCE') {
      return _ssceExams.isNotEmpty ? _ssceExams : _allExams;
    }
    return _allExams;
  }

  String get _tabLabel {
    if (_activeTab == 'JAMB') return 'JAMB';
    if (_activeTab == 'JUNIOR_WAEC') return 'Junior WAEC';
    if (_activeTab == 'COMMON_ENTRANCE') return 'Common Entrance';
    return 'WAEC / NECO';
  }

  bool get _isJambTab => _activeTab == 'JAMB';

  List<String> get _jambYears {
    final set = <String>{};
    for (final raw in _jambExams) {
      if (raw is! Map) continue;
      final y = _examYear(raw);
      if (y != null && y.isNotEmpty) set.add(y);
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<Map<String, dynamic>> _jambBundleMembersForYear(String year) {
    if (_jambSubjects.length != 4) return [];
    final exams = _jambExams
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final picks = <Map<String, dynamic>>[];
    for (final subj in _jambSubjects) {
      Map<String, dynamic>? found;
      for (final e in exams) {
        final y = _examYear(e);
        if (y != year) continue;
        if (subjectMatches(_examSubject(e), [subj])) {
          found = e;
          break;
        }
      }
      if (found == null) return [];
      picks.add(found);
    }
    return picks;
  }

  bool _jambBundleDownloadedForMembers(List<Map<String, dynamic>> members) {
    if (members.length != 4) return false;
    return members.every((e) => _downloaded.contains(e['id']?.toString() ?? ''));
  }

  List<String> get _subjects {
    // WAEC/NECO / Junior WAEC / Common Entrance: show profile subjects.
    if (_activeTab == 'WAEC_NECO' ||
        _activeTab == 'JUNIOR_WAEC' ||
        _activeTab == 'COMMON_ENTRANCE') {
      if (_ssceSubjects.isNotEmpty) return List<String>.from(_ssceSubjects);
    }
    // Fallback: subjects found in uploaded exams.
    final set = <String>{};
    for (final raw in _tabExams) {
      if (raw is! Map) continue;
      final s = _examSubject(Map<String, dynamic>.from(raw));
      if (s.isNotEmpty) set.add(s);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _ensureDefaultSubject() {
    if (_isJambTab) return;
    final subjects = _subjects;
    if (subjects.isEmpty) return;
    if (_selectedSubject == null ||
        !subjects.any((s) => s.toLowerCase() == _selectedSubject!.toLowerCase())) {
      _selectedSubject = subjects.first;
    }
  }

  List<Map<String, dynamic>> get _filteredExams {
    final subject = (_selectedSubject ?? '').trim();
    final list = _tabExams
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) {
          if (subject.isEmpty) return true;
          return subjectMatches(_examSubject(e), [subject]);
        })
        .toList();
    list.sort((a, b) {
      final sa = _examSubject(a).toLowerCase();
      final sb = _examSubject(b).toLowerCase();
      return sa.compareTo(sb);
    });
    return list;
  }

  String _jambBundleBusyKey(String year) => 'jamb_bundle_$year';

  Future<void> _downloadJambBundleMembers(
    String year,
    List<Map<String, dynamic>> members,
  ) async {
    if (members.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All 4 JAMB subject packs must be available from admin.'),
        ),
      );
      return;
    }
    if (_busyExamId != null) return;
    setState(() => _busyExamId = _jambBundleBusyKey(year));
    try {
      for (final exam in members) {
        final id = exam['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final pack = await _api.cbtDownloadExamRaw(id);
        await _store.savePack(id, pack);
      }
      final ids = await _store.downloadedIds();
      if (!mounted) return;
      setState(() => _downloaded = ids);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('JAMB full exam downloaded — 4 subjects ready offline.'),
        ),
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

  Future<void> _startJambBundleMembers(
    BuildContext ctx,
    String year,
    List<Map<String, dynamic>> members,
  ) async {
    if (members.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need all 4 JAMB subject exams uploaded by admin.'),
        ),
      );
      return;
    }
    // Start never auto-downloads — user must tap Download first.
    for (final exam in members) {
      final id = exam['id']?.toString() ?? '';
      if (id.isEmpty || !_downloaded.contains(id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download this exam first, then tap Start.'),
          ),
        );
        return;
      }
    }
    if (_busyExamId != null) return;
    setState(() => _busyExamId = _jambBundleBusyKey(year));
    try {
      final allQuestions = <CbtQuestion>[];
      final sectionStarts = <String, int>{};
      var totalDuration = 0;
      for (final exam in members) {
        final id = exam['id']?.toString() ?? '';
        final rawSubject = _examSubject(exam);
        final rawTitle = exam['title']?.toString().trim() ?? '';
        var subjectLabel = rawSubject.isNotEmpty
            ? rawSubject
            : (rawTitle.isNotEmpty ? rawTitle : 'Subject');
        // Ensure each section label is unique so the dropdown shows all sections.
        if (sectionStarts.containsKey(subjectLabel)) {
          var suffix = 2;
          while (sectionStarts.containsKey('$subjectLabel $suffix')) {
            suffix++;
          }
          subjectLabel = '$subjectLabel $suffix';
        }
        sectionStarts[subjectLabel] = allQuestions.length + 1;
        final pack = await _store.loadPack(id);
        if (pack == null) {
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('Download this exam first, then tap Start.'),
            ),
          );
          return;
        }
        totalDuration = max(
          totalDuration,
          (pack['duration_minutes'] as num?)?.toInt() ?? 0,
        );
        final rawQs = (pack['questions'] as List?) ?? [];
        for (final q in rawQs.whereType<Map>()) {
          final map = Map<String, dynamic>.from(q);
          final img = map['image_url']?.toString() ??
              map['diagram_url']?.toString() ??
              map['image']?.toString();
          if (img != null && img.isNotEmpty) {
            map['image_url'] = _api.resolveMediaUrl(img);
          }
          allQuestions.add(CbtQuestion.fromJson(map));
        }
      }
      if (!ctx.mounted) return;
      final title =
          'JAMB Full Exam (${_jambSubjects.join(' · ')}) · $year';
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => CbtExamScreen(
            subject: title,
            totalQuestions: allQuestions.length,
            durationSeconds: (totalDuration > 0 ? totalDuration : 120) * 60,
            questions: allQuestions,
            sectionStarts: sectionStarts,
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
    // Start never auto-downloads — user must tap Download first.
    if (!_downloaded.contains(examId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download this exam first, then tap Start.'),
        ),
      );
      return;
    }
    if (_busyExamId != null) return;
    setState(() => _busyExamId = examId);
    try {
      var pack = await _store.loadPack(examId);
      if (pack == null) {
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('Download this exam first, then tap Start.'),
          ),
        );
        return;
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
                                  b == 'WAEC_NECO' ||
                                  b == 'JUNIOR_WAEC' ||
                                  b == 'COMMON_ENTRANCE'))) ...[
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (_boards.contains('JAMB'))
                              _boardTab(context, 'JAMB', 'JAMB'),
                            if (_boards.contains('WAEC_NECO'))
                              _boardTab(context, 'WAEC / NECO', 'WAEC_NECO'),
                            if (_boards.contains('JUNIOR_WAEC'))
                              _boardTab(context, 'Junior WAEC', 'JUNIOR_WAEC'),
                            if (_boards.contains('COMMON_ENTRANCE'))
                              _boardTab(
                                  context, 'Common Entrance', 'COMMON_ENTRANCE'),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (_loadingExams)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: CircularProgressIndicator(
                                color: context.accentColor),
                          ),
                        )
                      else if (_isJambTab) ...[
                        Text(
                          'JAMB — choose the pack you want',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Each option downloads your 4 JAMB subjects together and starts as one full UTME exam.',
                          style: TextStyle(
                              color: context.greyColor,
                              fontSize: 12,
                              height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        Builder(
                          builder: (ctx) {
                            final years = _jambYears;
                            final validYears = <String>[];
                            for (final y in years) {
                              final members = _jambBundleMembersForYear(y);
                              if (members.length == 4) validYears.add(y);
                            }

                            if (validYears.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return Column(
                              children: validYears.map((y) {
                                final members = _jambBundleMembersForYear(y);
                                final isDownloaded =
                                    _jambBundleDownloadedForMembers(members);
                                final totalQ = members.fold<int>(
                                  0,
                                  (sum, e) =>
                                      sum + ((e['total_questions'] as num?)?.toInt() ?? 0),
                                );
                                final durationMins = members.fold<int>(
                                  0,
                                  (maxDur, e) => maxDur >
                                          ((e['duration_minutes'] as num?)?.toInt() ?? 0)
                                      ? maxDur
                                      : ((e['duration_minutes'] as num?)?.toInt() ?? 0),
                                );

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _ExamCard(
                                    title: 'JAMB Full Exam',
                                    description:
                                        'Year $y · Subjects: ${_jambSubjects.join(' · ')}',
                                    examType: '4 subjects · combined',
                                    durationMins: durationMins > 0 ? durationMins : 120,
                                    totalQuestions: totalQ,
                                    isBusy: _busyExamId == _jambBundleBusyKey(y),
                                    isDownloaded: isDownloaded,
                                    onDownload: () => _downloadJambBundleMembers(y, members),
                                    onStart: () => _startJambBundleMembers(ctx, y, members),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ] else if (subjects.isEmpty)
                        _emptyBox(context)
                      else ...[
                        Text(
                          'Choose subject',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 42,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: subjects.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final s = subjects[i];
                              return _subjectChip(context, s, s);
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (exams.isEmpty)
                          const SizedBox.shrink()
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
                            final downloaded = _downloaded.contains(id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _ExamCard(
                                title: title,
                                description: desc,
                                examType: type,
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
        _ensureDefaultSubject();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    return GestureDetector(
      onTap: () => setState(() => _selectedSubject = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? context.accentColor : context.cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: sel ? context.accentColor : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel
                ? (context.isDark ? AppColors.background : Colors.white)
                : context.textColor,
            fontSize: 13,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _emptyBox(BuildContext context, {String? message}) {
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
            message ??
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
                  onPressed: (isBusy || !isDownloaded) ? null : onStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor:
                        context.isDark ? AppColors.background : Colors.white,
                    disabledBackgroundColor:
                        context.accentColor.withOpacity(0.35),
                    disabledForegroundColor:
                        (context.isDark ? AppColors.background : Colors.white)
                            .withOpacity(0.7),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    minimumSize: const Size(0, 42),
                  ),
                  child: Text(
                    isDownloaded ? 'Start offline' : 'Download first',
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
