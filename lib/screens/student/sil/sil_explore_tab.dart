import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'sil_models.dart';
import 'sil_quiz_screen.dart';
import 'sil_widgets.dart';

class SilExploreTab extends StatelessWidget {
  final SilProfile profile;
  final bool offline;
  final ValueChanged<SilProfile> onProfileUpdate;

  const SilExploreTab({
    super.key,
    required this.profile,
    required this.offline,
    required this.onProfileUpdate,
  });

  static const _cats = [
    ('General Knowledge', Icons.psychology_rounded, Color(0xFF7C3AED), '1250'),
    ('Science', Icons.science_rounded, Color(0xFF06B6D4), '980'),
    ('History', Icons.account_balance_rounded, Color(0xFFF59E0B), '740'),
    ('Sports', Icons.sports_soccer_rounded, Color(0xFF22C55E), '620'),
    ('Entertainment', Icons.movie_rounded, Color(0xFFEC4899), '510'),
    ('Space', Icons.public_rounded, Color(0xFF6366F1), '430'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('Quiz Categories',
              style: TextStyle(
                  color: context.textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Choose a category and start playing!',
              style: TextStyle(color: context.greyColor)),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search quizzes...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: SilColors.purpleSoft.withOpacity(0.45),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: ['All', 'General', 'Science', 'History', 'Sports']
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          label: Text(c),
                          backgroundColor: c == 'All'
                              ? SilColors.purple
                              : SilColors.purpleSoft,
                          labelStyle: TextStyle(
                            color: c == 'All' ? Colors.white : SilColors.purple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SilSectionTitle(title: 'Recommended for you'),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: _cats.map((c) {
              return Material(
                color: context.isDark ? const Color(0xFF1A1228) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SilQuizScreen(
                          mode: 'practice',
                          subject: c.$1,
                          profile: profile,
                          offline: offline,
                          onProfileUpdate: onProfileUpdate,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: c.$3.withOpacity(0.15),
                          child: Icon(c.$2, color: c.$3),
                        ),
                        const Spacer(),
                        Text(c.$1,
                            style: TextStyle(
                                color: context.textColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                        Text('${c.$4} Questions',
                            style: TextStyle(
                                color: context.greyColor, fontSize: 11)),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: SilColors.purple,
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
