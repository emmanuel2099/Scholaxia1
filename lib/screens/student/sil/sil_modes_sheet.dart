import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'sil_models.dart';
import 'sil_quiz_screen.dart';
import 'sil_widgets.dart';

class SilModesSheet extends StatefulWidget {
  final String mode;
  final SilProfile profile;
  final bool offline;
  final ValueChanged<SilProfile> onProfileUpdate;

  const SilModesSheet({
    super.key,
    required this.mode,
    required this.profile,
    required this.offline,
    required this.onProfileUpdate,
  });

  @override
  State<SilModesSheet> createState() => _SilModesSheetState();
}

class _SilModesSheetState extends State<SilModesSheet> {
  int _aiLevel = 1;
  int _bet = 100;
  final _tagCtrl = TextEditingController();

  static const _ai = [
    (1, 'Beginner', 10, 20),
    (2, 'Easy', 25, 50),
    (3, 'Medium', 50, 100),
    (4, 'Hard', 100, 220),
    (5, 'Expert', 200, 450),
    (6, 'Genius', 400, 900),
  ];

  @override
  void dispose() {
    _tagCtrl.dispose();
    super.dispose();
  }

  void _play({int? level, int? bet, String? tag}) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SilQuizScreen(
          mode: widget.mode,
          subject: widget.mode == 'ai_challenge'
              ? 'AI Challenge L${level ?? 1}'
              : 'Student Challenge',
          profile: widget.profile,
          offline: widget.offline,
          onProfileUpdate: widget.onProfileUpdate,
          aiLevel: level,
          betCoins: bet,
          opponentTag: tag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.mode == 'ai_challenge'
                ? 'Play vs Computer'
                : widget.mode == 'student_challenge'
                    ? 'Challenge a Student'
                    : widget.mode == 'class_challenge'
                        ? 'Class Challenge (5v5)'
                        : 'School Challenge (10v10)',
            style: TextStyle(
              color: context.textColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text('Your class: ${widget.profile.academicClass}',
              style: TextStyle(color: context.greyColor)),
          const SizedBox(height: 16),
          if (widget.mode == 'ai_challenge') ...[
            ..._ai.map((l) {
              final locked = l.$1 > widget.profile.aiLevel;
              return ListTile(
                enabled: !locked,
                title: Text('Level ${l.$1} — ${l.$2}'),
                subtitle: Text('Entry ${l.$3} · Reward ${l.$4}'),
                trailing: locked
                    ? const Icon(Icons.lock_rounded)
                    : Radio<int>(
                        value: l.$1,
                        groupValue: _aiLevel,
                        activeColor: SilColors.purple,
                        onChanged: (v) => setState(() => _aiLevel = v ?? 1),
                      ),
                onTap: locked ? null : () => setState(() => _aiLevel = l.$1),
              );
            }),
            SilPrimaryButton(
              label: 'Start Level $_aiLevel',
              onPressed: () => _play(level: _aiLevel),
            ),
          ] else if (widget.mode == 'student_challenge') ...[
            Text('Bet amount (same class only)',
                style: TextStyle(
                    color: context.textColor, fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              children: [50, 100, 200, 500]
                  .map((b) => ChoiceChip(
                        label: Text('$b'),
                        selected: _bet == b,
                        selectedColor: SilColors.purpleSoft,
                        onSelected: (_) => setState(() => _bet = b),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagCtrl,
              decoration: InputDecoration(
                labelText: 'Opponent gamer tag (optional)',
                hintText: 'Leave empty to play open/bot match',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            Text('Winner gets 90% of pot · 10% platform fee',
                style: TextStyle(color: context.greyColor, fontSize: 12)),
            const SizedBox(height: 12),
            SilPrimaryButton(
              label: 'Start Challenge',
              onPressed: () => _play(
                bet: _bet,
                tag: _tagCtrl.text.trim().isEmpty
                    ? null
                    : _tagCtrl.text.trim(),
              ),
            ),
          ] else ...[
            Text(
              widget.mode == 'class_challenge'
                  ? 'Entry 100 coins · 10 questions · prize shared by winning class'
                  : 'Entry 200 coins · invite expires in 48 hours · school trophies',
              style: TextStyle(color: context.greyColor),
            ),
            const SizedBox(height: 16),
            SilPrimaryButton(
              label: 'Enter Challenge',
              onPressed: () => _play(bet: widget.mode == 'class_challenge' ? 100 : 200),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
