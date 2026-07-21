import 'package:flutter/material.dart';

import 'sil_league_header.dart';
import 'sil_models.dart';
import 'sil_widgets.dart';

/// Community tab — exact mockup UI.
class SilExploreTab extends StatefulWidget {
  final SilProfile profile;
  final bool offline;
  final ValueChanged<SilProfile> onProfileUpdate;

  const SilExploreTab({
    super.key,
    required this.profile,
    required this.offline,
    required this.onProfileUpdate,
  });

  @override
  State<SilExploreTab> createState() => _SilExploreTabState();
}

class _SilExploreTabState extends State<SilExploreTab> {
  int _filter = 0;
  int _feedTab = 0;
  final _postCtrl = TextEditingController();

  static const _filters = [
    ('All', Icons.apps_rounded),
    ('Discussions', Icons.forum_outlined),
    ('Study Tips', Icons.lightbulb_outline_rounded),
    ('Wins', Icons.emoji_events_outlined),
    ('Events', Icons.event_outlined),
    ('Clubs', Icons.groups_outlined),
  ];

  static const _feedTabs = ['For You', 'Following', 'My School'];

  @override
  void dispose() {
    _postCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
          children: [
            const SilLeagueHeader(),
            const SizedBox(height: 8),
            const Text(
              'Community',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            Text(
              'Connect, share and learn together.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final on = _filter == i;
                  final f = _filters[i];
                  return GestureDetector(
                    onTap: () => setState(() => _filter = i),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: on
                                ? SilColors.purple
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(f.$2,
                              color: on ? Colors.white : const Color(0xFF6B7280),
                              size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          f.$1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: on
                                ? SilColors.purple
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: SilColors.purpleSoft,
                    child: Text(
                      widget.profile.gamerTag.isNotEmpty
                          ? widget.profile.gamerTag[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                          color: SilColors.purple, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _postCtrl,
                      decoration: const InputDecoration(
                        hintText: "What's on your mind?",
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (_postCtrl.text.trim().isEmpty) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Post shared to Community')),
                      );
                      _postCtrl.clear();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SilColors.purple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text('Post',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: List.generate(_feedTabs.length, (i) {
                final on = _feedTab == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: GestureDetector(
                    onTap: () => setState(() => _feedTab = i),
                    child: Column(
                      children: [
                        Text(
                          _feedTabs[i],
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: on
                                ? SilColors.purple
                                : const Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 3,
                          width: 28,
                          decoration: BoxDecoration(
                            color: on ? SilColors.purple : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            _postCard(
              name: 'Adaeze Okafor',
              grade: 'JSS3',
              school: 'Queen\'s College',
              time: '2h ago',
              body:
                  'Just finished a Science quiz streak 🔥 Who wants a Student Challenge tomorrow?',
              likes: 24,
              comments: 8,
            ),
            _postCard(
              name: 'Chidi Nwosu',
              grade: 'SS1',
              school: 'King\'s College',
              time: '5h ago',
              body: 'Sharing my Top 10 GK Tips PDF for Friday National prep.',
              likes: 56,
              comments: 14,
              attachment: true,
            ),
            _postCard(
              name: 'Sarah Bello',
              grade: 'SS2',
              school: 'Scholaxia Academy',
              time: 'Yesterday',
              body:
                  'Our class won School Challenge! Represent your school — keep grinding 📚',
              likes: 91,
              comments: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _postCard({
    required String name,
    required String grade,
    required String school,
    required String time,
    required String body,
    required int likes,
    required int comments,
    bool attachment = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: SilColors.purpleSoft,
                child: Text(name[0],
                    style: const TextStyle(
                        color: SilColors.purple, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: SilColors.purpleSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(grade,
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: SilColors.purple)),
                        ),
                      ],
                    ),
                    Text('$school · $time',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz, color: Color(0xFF9CA3AF)),
            ],
          ),
          const SizedBox(height: 10),
          Text(body,
              style: const TextStyle(
                  fontSize: 13, height: 1.4, color: Color(0xFF111827))),
          if (attachment) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded,
                      color: Color(0xFFDC2626), size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Top 10 GK Tips.pdf',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 12)),
                        Text('PDF · Study resource',
                            style: TextStyle(
                                color: Color(0xFF6B7280), fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.download_rounded, color: SilColors.purple),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.thumb_up_alt_outlined,
                  size: 18, color: Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text('$likes',
                  style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
              const SizedBox(width: 16),
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 18, color: Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text('$comments',
                  style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
              const Spacer(),
              const Icon(Icons.bookmark_border_rounded,
                  size: 20, color: Color(0xFF6B7280)),
            ],
          ),
        ],
      ),
    );
  }
}
