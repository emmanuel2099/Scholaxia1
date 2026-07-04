import 'package:flutter/material.dart';
import '../services/live_class_ring_service.dart';
import '../api/api_service.dart';
import '../utils/subject_match.dart';
import '../widgets/access_code_popup.dart';

/// Polls for live-class access codes and shows a copy popup (desktop-style).
class AccessCodeService {
  AccessCodeService._();
  static final AccessCodeService instance = AccessCodeService._();

  final Set<String> _shownDeliveryIds = {};
  bool _dialogOpen = false;
  BuildContext? _hostContext;
  List<String>? _cachedSubjects;
  VoidCallback? onCodeReceived;

  void attach(BuildContext context) {
    _hostContext = context;
  }

  void detach() {
    _hostContext = null;
  }

  Future<List<String>> _studentSubjects(ApiService api) async {
    if (_cachedSubjects != null) return _cachedSubjects!;
    try {
      final profile = await api.getStudentProfile();
      _cachedSubjects = profile.subjects;
    } catch (_) {
      _cachedSubjects = [];
    }
    return _cachedSubjects!;
  }

  Future<void> poll(ApiService api) async {
    final ctx = _hostContext;
    if (ctx == null || !ctx.mounted || _dialogOpen) return;

    try {
      final subjects = await _studentSubjects(api);
      final data = await api.myAccessCodes();
      final codes = (data['codes'] as List?) ?? [];
      for (final raw in codes) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final id = map['id']?.toString() ?? '';
        final isRead = map['is_read'] == true;
        final isUsed = map['is_used'] == true;
        final classSubject = map['subject']?.toString() ?? '';
        if (id.isEmpty || isRead || isUsed || _shownDeliveryIds.contains(id)) {
          continue;
        }
        if (map['is_class_live'] == false) continue;
        // Only show popup for students who have this subject
        if (classSubject.isNotEmpty &&
            subjects.isNotEmpty &&
            !subjectMatches(classSubject, subjects)) {
          continue;
        }
        if (!ctx.mounted) return;
        LiveClassRingService.instance.resetStopFlag();
        await LiveClassRingService.instance.syncWithLiveStatus(api);
        await _showPopup(ctx, api, map);
        onCodeReceived?.call();
        break;
      }
    } catch (_) {}
  }

  Future<void> _showPopup(
    BuildContext context,
    ApiService api,
    Map<String, dynamic> code,
  ) async {
    final id = code['id']?.toString() ?? '';
    if (id.isEmpty) return;

    _dialogOpen = true;
    _shownDeliveryIds.add(id);

    await showAccessCodePopup(context, code);
    LiveClassRingService.instance.stop();
    try {
      await api.markAccessCodesRead();
    } catch (_) {}

    _dialogOpen = false;
  }
}
