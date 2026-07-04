import 'package:flutter/material.dart';

import '../../../models/saved_live_class.dart';
import '../../../services/saved_live_class_service.dart';
import '../../../theme/app_theme.dart';
import 'saved_class_player_screen.dart';

class SavedClassesScreen extends StatefulWidget {
  const SavedClassesScreen({super.key});

  @override
  State<SavedClassesScreen> createState() => SavedClassesScreenState();
}

class SavedClassesScreenState extends State<SavedClassesScreen> {
  final _service = SavedLiveClassService.instance;
  List<SavedLiveClass> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (mounted) setState(() => _loading = true);
    final rows = await _service.list();
    if (mounted) {
      setState(() {
        _items = rows;
        _loading = false;
      });
    }
  }

  Future<void> _delete(SavedLiveClass item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cardColor,
        title: Text('Delete saved class?',
            style: TextStyle(color: context.textColor)),
        content: Text(
          'Remove "${item.title}" from this device?',
          style: TextStyle(color: context.greyColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.delete(item.id);
    await reload();
  }

  String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day}/${local.year} · $h:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: context.accentColor,
          onRefresh: reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: AppGradients.primaryButton,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.video_library_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Saved Classes',
                                  style: TextStyle(
                                    color: context.textColor,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Recordings saved on this device only',
                                  style: TextStyle(
                                    color: context.greyColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save_alt_rounded,
                            size: 56, color: context.accentColor.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No saved classes yet',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'During a live class, tap Save class to record the lesson on your device. Watch again here anytime.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.greyColor, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(context, _items[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, SavedLiveClass item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.isVideo ? Icons.play_circle_outline : Icons.mic_none_rounded,
              color: context.accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: context.textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (item.subject.isNotEmpty) item.subject,
                    if (item.teacher.isNotEmpty) item.teacher,
                  ].join(' · '),
                  style: TextStyle(color: context.greyColor, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Saved ${_formatWhen(item.savedAt)}'
                  '${item.durationSeconds != null ? ' · ${(item.durationSeconds! / 60).ceil()} min' : ''}',
                  style: TextStyle(
                    color: context.greyColor.withOpacity(0.85),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SavedClassPlayerScreen(item: item),
                          ),
                        );
                      },
                      icon: Icon(Icons.play_arrow_rounded,
                          size: 18, color: context.accentColor),
                      label: Text('Watch',
                          style: TextStyle(color: context.accentColor)),
                    ),
                    TextButton.icon(
                      onPressed: () => _delete(item),
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      label: const Text('Delete',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}