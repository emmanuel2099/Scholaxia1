import 'dart:io';

import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../services/profile_avatar_cache.dart';
import '../theme/app_theme.dart';

/// Avatar for community / group posts (profile photo or initials).
class AuthorAvatar extends StatelessWidget {
  final String? pictureUrl;
  final String name;
  final double radius;
  final bool preferLocalCache;

  const AuthorAvatar({
    super.key,
    this.pictureUrl,
    required this.name,
    this.radius = 20,
    this.preferLocalCache = false,
  });

  String get _initial {
    final t = name.trim();
    if (t.isEmpty) return 'U';
    return t[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = ApiService().resolveMediaUrl(pictureUrl);
    return FutureBuilder<File?>(
      future: preferLocalCache
          ? ProfileAvatarCache.instance.existingFile()
          : Future.value(null),
      builder: (context, snap) {
        ImageProvider? image;
        if (snap.data != null) {
          image = FileImage(snap.data!);
        } else if (resolved.isNotEmpty) {
          image = NetworkImage(resolved);
        }
        return CircleAvatar(
          radius: radius,
          backgroundColor: context.accentColor.withOpacity(0.15),
          backgroundImage: image,
          onBackgroundImageError: image != null ? (_, __) {} : null,
          child: image == null
              ? Text(
                  _initial,
                  style: TextStyle(
                    color: context.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: radius * 0.85,
                  ),
                )
              : null,
        );
      },
    );
  }
}
