import 'dart:async';
import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';
import 'group_voice_call_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _api = ApiService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _groupInfo;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _pollTimer;
  String? _myUserId;
  bool _incomingShown = false;

  @override
  void initState() {
    super.initState();
    _api.getUserId().then((id) => _myUserId = id);
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _refreshMessages(silent: true);
      _checkIncomingCall();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _api.getStudentGroup(widget.groupId);
      if (info['is_member'] != true) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Join this group first to open the chat room.';
          });
        }
        return;
      }
      _groupInfo = info;
      await _refreshMessages(silent: false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is ApiException ? e.message : 'Could not load chat.';
        });
      }
    }
  }

  Future<void> _refreshMessages({required bool silent}) async {
    try {
      final raw = await _api.listGroupMessages(widget.groupId);
      final msgs = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _loading = false;
          _error = e is ApiException ? e.message : 'Could not load messages.';
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _checkIncomingCall() async {
    if (_incomingShown || !mounted) return;
    try {
      final call = await _api.getActiveGroupCall(widget.groupId);
      if (call == null || call['active'] != true) return;
      final callerId = call['caller_id']?.toString() ?? '';
      if (_myUserId != null &&
          callerId.isNotEmpty &&
          callerId.toLowerCase() == _myUserId!.toLowerCase()) {
        return;
      }
      _incomingShown = true;
      if (!mounted) return;
      await showIncomingGroupCall(
        context,
        groupId: widget.groupId,
        groupName: widget.groupName,
        callerName: call['caller_name']?.toString() ?? 'Member',
      );
      _incomingShown = false;
    } catch (_) {}
  }

  Future<void> _startCall() async {
    try {
      final data = await _api.startGroupVoiceCall(widget.groupId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupVoiceCallScreen(
            groupId: widget.groupId,
            groupName: widget.groupName,
            isCaller: true,
            initialToken: data,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : 'Could not start call'),
        ),
      );
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _inputCtrl.clear();
    setState(() => _sending = true);

    final optimistic = {
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'author_name': 'You',
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
      'is_mine': true,
      '_pending': true,
    };
    setState(() => _messages = [..._messages, optimistic]);
    _scrollToBottom();

    try {
      final sent = await _api.sendGroupMessage(widget.groupId, text);
      if (mounted) {
        setState(() {
          _messages = [
            ..._messages.where((m) => m['id'] != optimistic['id']),
            sent,
          ];
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages.where((m) => m['id'] != optimistic['id']).toList();
          _inputCtrl.text = text;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Could not send message.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = _groupInfo?['member_count'] ?? 0;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        elevation: 0,
        leading: const StudentBackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.groupName,
              style: TextStyle(
                color: context.textColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '$memberCount member${memberCount == 1 ? '' : 's'}',
              style: TextStyle(color: context.greyColor, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Group voice call',
            onPressed: _error != null ? null : _startCall,
            icon: Icon(Icons.call_rounded, color: context.accentColor),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: context.accentColor))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center,
                              style: TextStyle(color: context.greyColor)),
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              'No messages yet. Say hello to your group!',
                              style: TextStyle(color: context.greyColor),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) => _messageBubble(context, _messages[i]),
                          ),
          ),
          _inputBar(context),
        ],
      ),
    );
  }

  Widget _messageBubble(BuildContext context, Map<String, dynamic> m) {
    final mine = m['is_mine'] == true;
    final pending = m['_pending'] == true;
    final author = m['author_name']?.toString() ?? 'Student';
    final content = m['content']?.toString() ?? '';
    final time = _formatTime(m['created_at']?.toString());

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? context.accentColor.withOpacity(pending ? 0.5 : 1)
              : context.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                author,
                style: TextStyle(
                  color: context.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            Text(
              content,
              style: TextStyle(
                color: mine ? Colors.white : context.textColor,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                time,
                style: TextStyle(
                  color: mine ? Colors.white70 : context.greyColor,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: _error == null && !_loading,
              style: TextStyle(color: context.textColor),
              decoration: InputDecoration(
                hintText: 'Message your group…',
                hintStyle: TextStyle(color: context.greyColor),
                filled: true,
                fillColor: context.surfColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: context.accentColor,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              onTap: _sending ? null : _send,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
