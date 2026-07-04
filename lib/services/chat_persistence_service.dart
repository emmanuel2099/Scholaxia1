import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_service.dart';

/// One saved chat line (student/kind use [isAi]; teacher uses [role]).
class StoredChatMessage {
  final bool isAi;
  final String text;
  final String? time;
  final String? role;

  const StoredChatMessage({
    required this.isAi,
    required this.text,
    this.time,
    this.role,
  });

  Map<String, dynamic> toJson() => {
        'isAi': isAi,
        'text': text,
        if (time != null) 'time': time,
        if (role != null) 'role': role,
      };

  factory StoredChatMessage.fromJson(Map<String, dynamic> json) {
    return StoredChatMessage(
      isAi: json['isAi'] as bool? ?? json['role'] != 'user',
      text: json['text'] as String? ?? '',
      time: json['time'] as String?,
      role: json['role'] as String?,
    );
  }
}

/// Saves AI chat locally so it survives tab switches and app restarts.
class ChatPersistenceService {
  ChatPersistenceService._();
  static final instance = ChatPersistenceService._();

  static const _maxMessages = 150;

  Future<String> _storageKey(String channel) async {
    final uid = await ApiService().getUserId();
    final role = await ApiService().getRole();
    final suffix = (uid != null && uid.isNotEmpty) ? uid : (role ?? 'guest');
    return 'scholaxia_chat_${channel}_$suffix';
  }

  Future<List<StoredChatMessage>> load(String channel) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _storageKey(channel));
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => StoredChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .where((m) => m.text.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(String channel, List<StoredChatMessage> messages) async {
    if (messages.isEmpty) return;
    final trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(trimmed.map((m) => m.toJson()).toList());
    await prefs.setString(await _storageKey(channel), encoded);
  }

  Future<void> clear(String channel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _storageKey(channel));
  }
}
