import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../student/groups/groups_panel.dart';
import 'kind_shared.dart';

class KindGroupsScreen extends StatelessWidget {
  const KindGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeArea(
            bottom: false,
            child: KindHeroHeader(
              greeting: 'Groups',
              subtitle: 'Join or create a study group with friends.',
              icon: Icons.groups_rounded,
            ),
          ),
          const Expanded(child: GroupsPanel()),
        ],
      ),
    );
  }
}
