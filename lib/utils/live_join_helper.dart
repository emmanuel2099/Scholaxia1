import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../screens/student/classes/class_packages_screen.dart';
import '../screens/student/classes/live_class_screen.dart';
import '../services/live_class_ring_service.dart';
import '../widgets/join_live_dialog.dart';

bool _accessAllowsJoin(Map<String, dynamic> access) {
  return access['paid'] == true || access['can_join'] == true;
}

bool _accessNeedsPlan(Map<String, dynamic> access) {
  final vis = (access['visibility'] ?? '').toString().toLowerCase();
  // Private / public / school-group invites are always free.
  if (access['is_free'] == true ||
      vis == 'private' ||
      vis == 'public' ||
      vis == 'school_group') {
    return false;
  }
  if (_accessAllowsJoin(access)) return false;
  return access['need_plan'] == true ||
      access['requires_payment'] == true ||
      access['paid'] == false;
}

Future<bool> _offerSubscription(BuildContext context, String message) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Subscription required'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Open Subscription'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ClassPackagesScreen()),
  );
  return true;
}

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

    // If the student already paid on Subscription, the access endpoint
    // reflects that before we attempt join.
    try {
      final access = await api.getLiveClassAccess(classId);
      if (_accessNeedsPlan(access)) {
        if (!context.mounted) return;
        await _offerSubscription(
          context,
          'You need an active live class subscription to join this class. '
          'Pay on the Subscription screen, then join again.',
        );
        return;
      }
    } on ApiException {
      // Fall through — server still enforces on join.
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
  } on ApiException catch (e) {
    if (!context.mounted) return;
    final msg = e.message.toLowerCase();
    final needsSub = e.statusCode == 402 ||
        msg.contains('plan') ||
        msg.contains('subscription');
    if (needsSub) {
      await _offerSubscription(
        context,
        e.message.isNotEmpty
            ? e.message
            : 'Choose a live class plan on Subscription before joining.',
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message)),
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
