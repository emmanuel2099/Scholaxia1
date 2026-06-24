import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';

class JoinChannelScreen extends StatefulWidget {
  final String channelId;
  final String channelName;

  const JoinChannelScreen({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  State<JoinChannelScreen> createState() => _JoinChannelScreenState();
}

class _JoinChannelScreenState extends State<JoinChannelScreen> {
  final _api = ApiService();
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      await _api.joinChannel(channelId: widget.channelId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('already') && msg.contains('member')) {
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final btnFg = context.isDark ? AppColors.background : Colors.white;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        foregroundColor: context.textColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textColor),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text('Join Channel',
            style: TextStyle(
                color: context.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.borderColor),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.accentColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.people_alt_outlined,
                  color: context.accentColor, size: 44),
            ),
            const SizedBox(height: 24),
            Text(
              widget.channelName,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Join this channel to start posting,\nliking, and engaging with your class.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.greyColor, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 32),
            _infoRow(context, Icons.visibility_outlined,
                'See posts from classmates and teachers'),
            const SizedBox(height: 14),
            _infoRow(context, Icons.edit_outlined, 'Create and share posts'),
            const SizedBox(height: 14),
            _infoRow(context, Icons.thumb_up_outlined, 'Like and comment on posts'),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _joining ? null : _join,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentColor,
                  foregroundColor: btnFg,
                  disabledBackgroundColor: context.greyColor.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _joining
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: btnFg))
                    : Text('Join ${widget.channelName}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: btnFg)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Maybe later',
                  style: TextStyle(color: context.greyColor, fontSize: 14)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    return Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: context.accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: context.accentColor, size: 20),
      ),
      const SizedBox(width: 14),
      Expanded(
          child: Text(text,
              style: TextStyle(color: context.textColor, fontSize: 14))),
    ]);
  }
}
