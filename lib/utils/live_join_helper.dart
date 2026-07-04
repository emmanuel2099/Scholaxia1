import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../screens/student/classes/live_class_screen.dart';
import '../services/live_class_ring_service.dart';
import '../widgets/join_live_dialog.dart';

/// Join a live class using an access code (same flow as desktop).
Future<void> joinLiveWithAccessCode(
  BuildContext context,
  ApiService api, {
  String? initialCode,
}) async {
  final code = await showJoinLiveCodeDialog(context, initialCode: initialCode);
  if (code == null || code.isEmpty || !context.mounted) return;

  try {
    LiveClassRingService.instance.stop();
    final preview = await api.joinPreviewByCode(code);
    final classId = preview['id']?.toString() ?? '';
    if (classId.isEmpty) {
      throw ApiException(404, 'Invalid code. Check the code from your popup.');
    }

    final data = await api.joinLiveClassByCode(code);
    final userId = await api.getUserId() ?? 'student';
    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveClassScreen(
          classId: classId,
          subject: data['subject']?.toString() ??
              preview['subject']?.toString() ??
              'General',
          topic: data['title']?.toString() ??
              preview['title']?.toString() ??
              'Live Class',
          userId: userId,
          roomId: data['room_id']?.toString() ?? data['channel_id']?.toString(),
          livekitToken: data['livekit_token']?.toString() ?? data['token']?.toString(),
          livekitUrl: data['livekit_url']?.toString(),
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          e is ApiException ? e.message : 'Could not join with this code.',
        ),
      ),
    );
  }
}
