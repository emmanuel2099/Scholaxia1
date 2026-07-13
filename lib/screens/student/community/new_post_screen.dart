import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/post_attachment_picker.dart';
import '../../../widgets/voice_note_recorder.dart';

class NewPostScreen extends StatefulWidget {
  final List<String> channels;
  final Map<String, String> channelIdMap; // name -> id
  const NewPostScreen({super.key, required this.channels, this.channelIdMap = const {}});

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  final _api = ApiService();
  final _textCtrl = TextEditingController();
  String _selectedChannel = '';
  bool _posting = false;

  String? _attachedFileUrl;
  String? _attachedFileType;
  String? _attachedFileName;
  bool _uploading = false;
  bool _recordingVoice = false;
  List<int>? _voiceBytes;
  String? _voiceFilename;

  @override
  void initState() {
    super.initState();
    if (widget.channels.isNotEmpty) _selectedChannel = widget.channels.first;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  String get _channelId =>
      widget.channelIdMap.isNotEmpty
          ? (widget.channelIdMap[_selectedChannel] ?? _selectedChannel)
          : _selectedChannel;

  Future<void> _pickPhoto() async {
    final picked = await pickPostAttachment('photo');
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final res = await _api.communityUpload(picked.bytes, picked.name);
      setState(() {
        _attachedFileUrl = res['file_url'] as String?;
        _attachedFileType = res['file_type'] as String?;
        _attachedFileName = picked.name;
        _uploading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
      setState(() => _uploading = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not upload photo. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _uploading = false);
    }
  }

  void _removeAttachment() {
    setState(() {
      _attachedFileUrl = null;
      _attachedFileType = null;
      _attachedFileName = null;
    });
  }

  Future<void> _post() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _attachedFileUrl == null && _voiceBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Write something, attach a photo, or record voice.')),
      );
      return;
    }

    setState(() => _posting = true);
    try {
      String? mediaUrl = _attachedFileUrl;
      String? mediaType = _attachedFileType;
      if (_voiceBytes != null && _voiceFilename != null) {
        final res = await _api.communityUpload(_voiceBytes!, _voiceFilename!);
        mediaUrl = res['file_url'] as String?;
        mediaType = 'audio';
      }
      final post = await _api.createPost(
        channelId: _channelId,
        content: text.isEmpty ? 'Voice note' : text,
        isAnonymous: false,
        visibility: 'everyone',
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      if (!mounted) return;
      Navigator.pop(context, post);
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('join') || msg.contains('member') || msg.contains('not a member')) {
        Navigator.pop(context, 'join_required');
      } else if (msg.contains('invalid token') ||
          msg.contains('community session') ||
          msg.contains('not authenticated')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log out and log back in, then try posting again.'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (e.statusCode == 404) {
        try {
          final msg = await _api.sendMessage(channelId: _channelId, content: text);
          if (!mounted) return;
          Navigator.pop(context, {
            'id': msg['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
            'content': text,
            'author_name': 'You',
            'is_anonymous': false,
            'created_at': DateTime.now().toIso8601String(),
            'like_count': 0,
            'liked_by_me': false,
          });
        } on ApiException catch (e2) {
          if (!mounted) return;
          final m = e2.message.toLowerCase();
          if (m.contains('join') || m.contains('member')) {
            Navigator.pop(context, 'join_required');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e2.message), backgroundColor: Colors.red),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postBtnFg = context.isDark ? AppColors.background : Colors.white;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        foregroundColor: context.textColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'New Post',
          style: TextStyle(
            color: context.textColor,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: ElevatedButton(
              onPressed: _posting ? null : _post,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: postBtnFg,
                disabledBackgroundColor: context.greyColor.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                elevation: 0,
              ),
              child: _posting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: postBtnFg),
                    )
                  : const Text('Post', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.borderColor),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.channels.isNotEmpty) ...[
              Text(
                'POST TO CHANNEL',
                style: TextStyle(
                  color: context.greyColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: widget.channels.map((ch) {
                    final sel = ch == _selectedChannel;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedChannel = ch),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? context.accentColor : context.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel ? context.accentColor : context.borderColor,
                          ),
                        ),
                        child: Text(
                          ch,
                          style: TextStyle(
                            color: sel
                                ? (context.isDark ? AppColors.background : Colors.white)
                                : context.textColor,
                            fontSize: 13,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.surfColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: context.cardColor,
                    child: Icon(Icons.person, color: context.greyColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      maxLines: 8,
                      maxLength: 500,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: context.textColor, fontSize: 15, height: 1.5),
                      decoration: InputDecoration(
                        hintText: 'Share something with your class...',
                        hintStyle: TextStyle(color: context.greyColor, fontSize: 15),
                        border: InputBorder.none,
                        counterText: '${_textCtrl.text.length}/500',
                        counterStyle: TextStyle(color: context.greyColor, fontSize: 11),
                        suffixIcon: InlineVoiceMicButton(
                          hasRecording: _voiceBytes != null,
                          onRecordingChanged: (v) =>
                              setState(() => _recordingVoice = v),
                          onRecorded: (bytes, name) => setState(() {
                            _voiceBytes = bytes;
                            _voiceFilename = name;
                            _attachedFileUrl = null;
                            _attachedFileType = null;
                            _recordingVoice = false;
                          }),
                          onCleared: () => setState(() {
                            _voiceBytes = null;
                            _voiceFilename = null;
                          }),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_recordingVoice)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Recording… tap stop when done',
                    style: TextStyle(color: Colors.red.shade400, fontSize: 12)),
              ),
            if (_voiceBytes != null && !_recordingVoice)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.mic_rounded, color: context.accentColor, size: 16),
                  const SizedBox(width: 6),
                  Text('Voice note ready',
                      style: TextStyle(color: context.greyColor, fontSize: 12)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() {
                      _voiceBytes = null;
                      _voiceFilename = null;
                    }),
                    child: Icon(Icons.close, color: context.greyColor, size: 18),
                  ),
                ]),
              ),
            if (_uploading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: context.accentColor),
                  ),
                  const SizedBox(width: 10),
                  Text('Uploading photo...', style: TextStyle(color: context.greyColor, fontSize: 13)),
                ]),
              ),
            if (_attachedFileName != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.accentColor.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.image_outlined, color: context.accentColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _attachedFileName!,
                      style: TextStyle(color: context.textColor, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: _removeAttachment,
                    child: Icon(Icons.close, color: context.greyColor, size: 18),
                  ),
                ]),
              ),
            const SizedBox(height: 24),
            Text(
              'ATTACHMENTS',
              style: TextStyle(
                color: context.greyColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _uploading ? null : _pickPhoto,
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: context.accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.image_outlined, color: context.accentColor, size: 26),
                  ),
                  const SizedBox(height: 6),
                  Text('Photo', style: TextStyle(color: context.textColor, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
