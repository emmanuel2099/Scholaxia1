import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';

class AssignmentScreen extends StatefulWidget {
  const AssignmentScreen({super.key});

  @override
  State<AssignmentScreen> createState() => _AssignmentScreenState();
}

class _AssignmentScreenState extends State<AssignmentScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _caption = TextEditingController();
  late final TabController _tabs;
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _teachers = [];
  String? _teacherId;
  String _channelId = '';
  PlatformFile? _pdf;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _api.communityChannels(),
        _api.listTeacherAnnouncements(),
        _api.listPublicTeachers(),
        _api.myAssignmentSubmissions(),
      ]);
      final channels = values[0];
      for (final raw in channels.whereType<Map>()) {
        final ch = Map<String, dynamic>.from(raw);
        final marker =
            '${ch['name']} ${ch['channel_type']}'.toLowerCase();
        if (marker.contains('announcement') || marker.contains('teacher')) {
          _channelId = ch['id']?.toString() ?? '';
          break;
        }
      }
      if (mounted) {
        setState(() {
          _announcements = values[1]
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((p) =>
                  p['media_type']?.toString().toLowerCase() == 'pdf' &&
                  p['media_url']?.toString().isNotEmpty == true)
              .toList();
          _teachers = values[2]
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _results = values[3]
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _teacherId ??= _teachers.isNotEmpty
              ? _teachers.first['user_id']?.toString()
              : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null) {
      _show('Could not read that PDF.', error: true);
      return;
    }
    setState(() => _pdf = file);
  }

  Future<void> _submit() async {
    if (_pdf?.bytes == null || _teacherId == null || _channelId.isEmpty) {
      _show('Choose a teacher and your completed PDF first.', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final uploaded = await _api.communityUpload(_pdf!.bytes!, _pdf!.name);
      final url = uploaded['file_url']?.toString() ?? '';
      if (url.isEmpty) throw ApiException.message('PDF upload failed.');
      await _api.submitAssignment(
        channelId: _channelId,
        teacherId: _teacherId!,
        fileUrl: url,
        caption: _caption.text,
      );
      if (!mounted) return;
      setState(() {
        _pdf = null;
        _caption.clear();
      });
      _show('Assignment submitted. Your teacher has been notified.');
      await _load();
      _tabs.animateTo(1);
    } on ApiException catch (e) {
      _show(e.message, error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _show(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  void _openPdf(String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssignmentPdfScreen(url: url, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('Assignments'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Submit Assignment'),
            Tab(text: 'Notice Board'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_submitTab(), _noticeBoard()],
            ),
    );
  }

  Widget _submitTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          const StudentSectionTitle(title: 'Teacher assignments'),
          if (_announcements.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No PDF assignments have been posted yet.'),
              ),
            )
          else
            ..._announcements.map((item) {
              final title =
                  item['content']?.toString().trim() ?? 'PDF assignment';
              final url = item['media_url']?.toString() ?? '';
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf_rounded,
                      color: Colors.red),
                  title: Text(title, maxLines: 2),
                  subtitle: Text(
                    item['author_name']?.toString() ?? 'Teacher',
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => _openPdf(url, title),
                ),
              );
            }),
          const StudentSectionTitle(title: 'Submit your completed PDF'),
          DropdownButtonFormField<String>(
            initialValue: _teacherId,
            decoration: const InputDecoration(
              labelText: 'Tag teacher',
              border: OutlineInputBorder(),
            ),
            items: _teachers
                .map(
                  (t) => DropdownMenuItem(
                    value: t['user_id']?.toString(),
                    child: Text(t['full_name']?.toString() ?? 'Teacher'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _teacherId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            decoration: const InputDecoration(
              labelText: 'Assignment title or note',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _pickPdf,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(_pdf?.name ?? 'Choose completed PDF'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Submit to teacher'),
          ),
          const SizedBox(height: 8),
          Text(
            'Only you and the teacher you tag can see this submission.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.greyColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _noticeBoard() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          Text(
            'Your private results',
            style: TextStyle(
              color: context.textColor,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Other students cannot see your submissions, scores, or feedback.',
            style: TextStyle(color: context.greyColor),
          ),
          const SizedBox(height: 14),
          if (_results.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No assignment submissions yet.'),
              ),
            )
          else
            ..._results.map((item) {
              final score = item['result_score']?.toString();
              final feedback = item['result_feedback']?.toString();
              final status = item['status']?.toString() ?? 'submitted';
              return Card(
                child: ListTile(
                  leading: Icon(
                    score == null
                        ? Icons.hourglass_top_rounded
                        : Icons.verified_rounded,
                    color: score == null ? Colors.orange : Colors.green,
                  ),
                  title: Text(
                    item['caption']?.toString().trim().isNotEmpty == true
                        ? item['caption'].toString()
                        : 'Assignment submission',
                  ),
                  subtitle: Text(
                    score == null
                        ? 'Status: $status'
                        : 'Score: $score${feedback?.isNotEmpty == true ? '\n$feedback' : ''}',
                  ),
                  isThreeLine: feedback?.isNotEmpty == true,
                ),
              );
            }),
        ],
      ),
    );
  }
}

class AssignmentPdfScreen extends StatelessWidget {
  const AssignmentPdfScreen({
    super.key,
    required this.url,
    required this.title,
  });

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1)),
      body: PdfViewer.uri(Uri.parse(url)),
    );
  }
}
