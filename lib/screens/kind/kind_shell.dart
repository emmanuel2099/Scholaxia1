import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'kind_home_screen.dart';
import 'kind_learn_screen.dart';
import 'kind_profile_screen.dart';
import 'kind_shared.dart';
import 'kind_sia_screen.dart';

/// Kid learner app — separate from the student (exam prep) experience.
class KindShell extends StatefulWidget {
  const KindShell({super.key});

  @override
  State<KindShell> createState() => _KindShellState();
}

class _KindShellState extends State<KindShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        final screens = [
          const KindHomeScreen(),
          const KindSiaScreen(),
          const KindLearnScreen(),
          const KindProfileScreen(),
        ];
        return Scaffold(
          backgroundColor: context.bgColor,
          body: IndexedStack(index: _index, children: screens),
          bottomNavigationBar: Container(
            height: 68,
            decoration: BoxDecoration(
              color: context.headerColor,
              border: Border(top: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _nav(context, 0, Icons.home_rounded, 'Home'),
                _nav(context, 1, Icons.auto_awesome, 'Sia'),
                _nav(context, 2, Icons.menu_book_rounded, 'Learn'),
                _nav(context, 3, Icons.face_retouching_natural, 'Me'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _nav(BuildContext context, int i, IconData icon, String label) {
    final active = _index == i;
    final accent = KidColors.accent;
    final muted = context.greyColor;
    return GestureDetector(
      onTap: () => setState(() => _index = i),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? accent : muted, size: 22),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  color: active ? accent : muted,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}
