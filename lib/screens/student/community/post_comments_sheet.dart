import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';

class PostCommentsSheet extends StatefulWidget {
  final String postId;
  final String channelId;
  final String postAuthor;
  final void Function(int count)? onCountChanged;

  const PostCommentsSheet({
    super.key,
    required this.postId,
    required this.channelId,
    required this.postAuthor,
    this.onCountChanged,
  });

  @override
  State<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  List<dynamic> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _api.getPostComments(
      postId: widget.postId,
      channelId: widget.channelId,
    );
    if (mounted) {
      setState(() {
        _comments = data;
        _loading = false;
      });
      widget.onCountChanged?.call(data.length);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.addPostComment(
        postId: widget.postId,
        channelId: widget.channelId,
        content: text,
      );
      _ctrl.clear();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentColor;
    final sendFg = context.isDark ? AppColors.background : Colors.white;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Comments',
                style: TextStyle(
                    color: context.textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('On ${widget.postAuthor}\'s post',
                style: TextStyle(color: context.greyColor, fontSize: 12)),
            const SizedBox(height: 16),
            Flexible(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: accent))
                  : _comments.isEmpty
                      ? Center(
                          child: Text('No comments yet. Be the first!',
                              style: TextStyle(
                                  color: context.greyColor, fontSize: 13)),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _comments.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final c = _comments[i] as Map<String, dynamic>;
                            final author = c['author_name'] as String? ??
                                c['sender_name'] as String? ??
                                'Student';
                            final raw = c['content'] as String? ?? '';
                            final text = _api.parseCommentText(raw);
                            final initial = author.isNotEmpty
                                ? author[0].toUpperCase()
                                : '?';
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: accent.withOpacity(0.15),
                                  child: Text(initial,
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.surfColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: context.borderColor),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(author,
                                            style: TextStyle(
                                                color: context.textColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Text(text,
                                            style: TextStyle(
                                                color: context.textColor,
                                                fontSize: 13,
                                                height: 1.4)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              style: TextStyle(color: context.textColor, fontSize: 14),
              textInputAction: TextInputAction.send,
              autocorrect: true,
              enableSuggestions: false,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Write a comment...',
                hintStyle: TextStyle(color: context.greyColor),
                filled: true,
                fillColor: context.surfColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Material(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _sending ? null : _send,
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: _sending
                            ? Padding(
                                padding: const EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: sendFg),
                              )
                            : Icon(Icons.send_rounded, color: sendFg, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
