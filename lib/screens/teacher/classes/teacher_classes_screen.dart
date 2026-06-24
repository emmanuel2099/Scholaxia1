import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../student/classes/live_class_screen.dart';
import '../teacher_shared.dart';

class TeacherClassesScreen extends StatefulWidget {
  const TeacherClassesScreen({super.key});

  @override
  State<TeacherClassesScreen> createState() => _TeacherClassesScreenState();
}

class _TeacherClassesScreenState extends State<TeacherClassesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();
  bool _loading = true;
  String? _teacherName;
  int _unread = 0;
  List<Map<String, dynamic>> _live = [];
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _past = [];
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getTeacherMe(),
        _api.unreadNotificationCount(),
        _api.listLiveClasses(status: 'live'),
        _api.listLiveClasses(status: 'upcoming'),
        _api.listLiveClasses(status: 'past'),
      ]);
      var students = await _api.listLiveSessionRequests(status: 'approved');
      if (students.isEmpty) {
        students = await _api.listLiveSessionRequests();
      }
      if (!mounted) return;
      setState(() {
        _teacherName = (results[0] as Map)['full_name']?.toString();
        _unread = results[1] as int;
        _live = _toMaps(results[2] as List);
        _upcoming = _toMaps(results[3] as List);
        _past = _toMaps(results[4] as List);
        _students = _toMaps(students);
        _loading = false;
      });
      teacherUnreadCount.value = results[1] as int;
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _toMaps(List raw) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _showCreateClassSheet({String? subject, String? title, bool goLiveNow = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CreateClassSheet(
        api: _api,
        onCreated: _load,
        initialSubject: subject,
        initialTitle: title,
        initialGoLiveNow: goLiveNow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateClassSheet,
        backgroundColor: AppColors.yellow,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TeacherTopBar(
                api: _api,
                teacherName: _teacherName,
                unreadCount: _unread,
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Classes',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Manage your live classes and sessions.',
                      style: TextStyle(color: AppColors.grey, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicator: BoxDecoration(
                  color: AppColors.yellow,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.black,
                unselectedLabelColor: AppColors.grey,
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: 'Live (${_live.length})'),
                  Tab(text: 'Upcoming (${_upcoming.length})'),
                  Tab(text: 'Past (${_past.length})'),
                  Tab(text: 'Students (${_students.length})'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.yellow))
                  : RefreshIndicator(
                      color: AppColors.yellow,
                      onRefresh: _load,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _classList(_live, empty: 'No live classes right now.'),
                          _classList(_upcoming, empty: 'No upcoming classes.'),
                          _classList(_past, empty: 'No past classes yet.'),
                          _studentsList(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _classList(List<Map<String, dynamic>> classes, {required String empty}) {
    if (classes.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(child: Text(empty, style: const TextStyle(color: AppColors.grey))),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: classes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ClassCard(data: classes[i], api: _api, onChanged: _load),
    );
  }

  Widget _studentsList() {
    if (_students.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: const [
          SizedBox(height: 40),
          Icon(Icons.people_outline, color: AppColors.grey, size: 48),
          SizedBox(height: 12),
          Text(
            'No students assigned yet',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(
            'When admin assigns a student to you, they appear here so you can host a live class for them.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: _students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final s = _students[i];
        final name = s['student_name']?.toString() ?? 'Student';
        final subject = s['subject']?.toString() ?? 'Subject';
        final topic = s['topic']?.toString() ??
            s['message']?.toString() ??
            'Live session';
        final status = s['status']?.toString() ?? 'approved';
        final time = TeacherUtils.formatDateTime(
            s['preferred_time'] ?? s['created_at']);
        final color = TeacherUtils.subjectColor(subject);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        Text(subject,
                            style: TextStyle(color: color, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.yellow.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(
                          color: AppColors.yellow,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(topic,
                  style: const TextStyle(color: AppColors.grey, fontSize: 12)),
              if (time.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(time,
                      style:
                          const TextStyle(color: AppColors.grey, fontSize: 11)),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showCreateClassSheet(
                    subject: subject,
                    title: topic,
                    goLiveNow: true,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellow,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                  ),
                  child: const Text('Host class',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClassCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final ApiService api;
  final VoidCallback? onChanged;
  const _ClassCard({required this.data, required this.api, this.onChanged});

  String get _id => data['id']?.toString() ?? '';
  String get _subject => data['subject']?.toString() ?? 'Subject';
  String get _title => data['title']?.toString() ?? _subject;
  bool get _isLive => data['is_live'] == true;

  Future<void> _startClass(BuildContext context) async {
    if (_id.isEmpty) return;
    try {
      await api.startLiveClass(_id);
      final tokenData = await api.getLiveClassToken(_id);
      final roomId = tokenData['room_id']?.toString() ??
          tokenData['channel_id']?.toString() ??
          data['room_id']?.toString() ??
          _id;
      final userId = await api.getUserId() ?? '';
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveClassScreen(
            subject: _subject,
            topic: _title,
            classId: _id,
            roomId: roomId,
            livekitToken: tokenData['livekit_token']?.toString() ??
                tokenData['token']?.toString(),
            livekitUrl: tokenData['livekit_url']?.toString(),
            userId: userId,
            isTeacher: true,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _endClass(BuildContext context) async {
    if (_id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('End class?', style: TextStyle(color: AppColors.white)),
        content: const Text(
          'This will stop the live session for all students.',
          style: TextStyle(color: AppColors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Class', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await api.endLiveClass(_id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class ended.')),
      );
      onChanged?.call();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = TeacherUtils.subjectColor(_subject);
    final time = TeacherUtils.formatDateTime(data['start_time']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: _isLive ? color.withOpacity(0.4) : const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.school_outlined, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title,
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    Text(_subject,
                        style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                  ],
                ),
              ),
              if (_isLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule_outlined, color: AppColors.grey, size: 13),
              const SizedBox(width: 4),
              Text(time,
                  style: const TextStyle(color: AppColors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLive)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _startClass(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                    child: const Text('Go Live',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _endClass(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('End Class',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _startClass(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                ),
                child: const Text('Start Class',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateClassSheet extends StatefulWidget {
  final ApiService api;
  final VoidCallback onCreated;
  final String? initialSubject;
  final String? initialTitle;
  final bool initialGoLiveNow;
  const _CreateClassSheet({
    required this.api,
    required this.onCreated,
    this.initialSubject,
    this.initialTitle,
    this.initialGoLiveNow = false,
  });

  @override
  State<_CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends State<_CreateClassSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subjectCtrl;
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  bool _loading = false;
  late bool _goLiveNow;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle ?? '');
    _subjectCtrl = TextEditingController(text: widget.initialSubject ?? '');
    _goLiveNow = widget.initialGoLiveNow;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _enterClassroom(Map<String, dynamic> created) async {
    final classId = created['id']?.toString() ?? '';
    if (classId.isEmpty || !mounted) return;
    final title = _titleCtrl.text.trim();
    final subject = _subjectCtrl.text.trim();
    try {
      await widget.api.startLiveClass(classId);
      final tokenData = await widget.api.getLiveClassToken(classId);
      final roomId = tokenData['room_id']?.toString() ??
          tokenData['channel_id']?.toString() ??
          created['room_id']?.toString() ??
          classId;
      final userId = await widget.api.getUserId() ?? '';
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveClassScreen(
            subject: subject,
            topic: title,
            classId: classId,
            roomId: roomId,
            livekitToken: tokenData['livekit_token']?.toString() ??
                tokenData['token']?.toString(),
            livekitUrl: tokenData['livekit_url']?.toString(),
            userId: userId,
            isTeacher: true,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final subject = _subjectCtrl.text.trim();
    if (title.isEmpty || subject.isEmpty) return;
    setState(() => _loading = true);
    try {
      final created = await widget.api.createLiveClass(
        subject: subject,
        title: title,
        startTime: _goLiveNow ? null : _start.toUtc().toIso8601String(),
        goLiveNow: _goLiveNow,
      );
      if (_goLiveNow) {
        await _enterClassroom(created);
      } else if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Class scheduled successfully!')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Schedule Live Class',
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _field(_titleCtrl, 'Class title'),
          const SizedBox(height: 12),
          _field(_subjectCtrl, 'Subject (e.g. Mathematics)'),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Go live now',
                style: TextStyle(color: AppColors.white, fontSize: 14)),
            subtitle: const Text('Start immediately and open the classroom',
                style: TextStyle(color: AppColors.grey, fontSize: 12)),
            value: _goLiveNow,
            activeThumbColor: AppColors.yellow,
            onChanged: (v) => setState(() => _goLiveNow = v),
          ),
          if (!_goLiveNow)
            ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start time',
                style: TextStyle(color: AppColors.grey, fontSize: 12)),
            subtitle: Text(TeacherUtils.formatDateTime(_start.toIso8601String()),
                style: const TextStyle(color: AppColors.white)),
            trailing: const Icon(Icons.calendar_today, color: AppColors.yellow),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _start,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date == null || !mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(_start),
              );
              if (time == null || !mounted) return;
              setState(() {
                _start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
              });
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellow,
                foregroundColor: Colors.black,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _goLiveNow ? 'Go Live' : 'Create Class',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AppColors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.grey),
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
