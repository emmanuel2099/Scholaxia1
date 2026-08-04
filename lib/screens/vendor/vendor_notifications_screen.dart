import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import 'vendor_theme.dart';

class VendorNotificationsScreen extends StatefulWidget {
  const VendorNotificationsScreen({super.key});

  @override
  State<VendorNotificationsScreen> createState() =>
      _VendorNotificationsScreenState();
}

class _VendorNotificationsScreenState extends State<VendorNotificationsScreen> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.notifications();
      final mapped = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() => _items = mapped);
      await _api.markAllNotificationsRead();
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VendorTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: VendorTheme.text,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: VendorTheme.maroon))
          : RefreshIndicator(
              color: VendorTheme.maroon,
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 100),
                        Icon(Icons.notifications_none_rounded,
                            size: 48, color: VendorTheme.muted),
                        SizedBox(height: 12),
                        Center(
                          child: Text(
                            'No notifications yet',
                            style: TextStyle(
                              color: VendorTheme.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(height: 6),
                        Center(
                          child: Text(
                            'New orders and updates will show here',
                            style: TextStyle(color: VendorTheme.muted),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final n = _items[i];
                        final title = n['title']?.toString() ??
                            n['type']?.toString() ??
                            'Update';
                        final body = n['message']?.toString() ??
                            n['body']?.toString() ??
                            n['content']?.toString() ??
                            '';
                        final unread = n['is_read'] != true;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: VendorTheme.cardDecoration(radius: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: VendorTheme.maroonSoft,
                                child: Icon(
                                  unread
                                      ? Icons.notifications_active_rounded
                                      : Icons.notifications_none_rounded,
                                  color: VendorTheme.maroon,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        color: VendorTheme.text,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (body.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        body,
                                        style: const TextStyle(
                                          color: VendorTheme.muted,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
