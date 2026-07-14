import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../screens/student/notifications/notifications_screen.dart';
import '../screens/student/profile/profile_screen.dart';
import '../screens/kind/kind_profile_screen.dart';
import '../theme/app_theme.dart';

/// Notification bell + profile avatar for student/kid top bars.
class AppHeaderActions extends StatefulWidget {
  final bool lightOnGradient;
  final VoidCallback? onChanged;

  const AppHeaderActions({
    super.key,
    this.lightOnGradient = false,
    this.onChanged,
  });

  @override
  State<AppHeaderActions> createState() => _AppHeaderActionsState();
}

class _AppHeaderActionsState extends State<AppHeaderActions> {
  final _api = ApiService();
  int _unread = 0;
  String _initial = 'S';
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final count = await _api.unreadNotificationCount();
      final role = await _api.getRole();
      String initial = 'S';
      String? photo;
      if (role == 'kind') {
        final p = await _api.getKindMe();
        final name = p['full_name']?.toString() ?? '';
        if (name.isNotEmpty) initial = name[0].toUpperCase();
        photo = p['profile_picture']?.toString();
      } else {
        final p = await _api.getStudentProfile();
        final name = p.fullName;
        if (name.isNotEmpty) initial = name[0].toUpperCase();
        photo = p.profilePicture;
      }
      if (mounted) {
        setState(() {
          _unread = count;
          _initial = initial;
          _photoUrl = (photo != null && photo.isNotEmpty)
              ? _api.resolveMediaUrl(photo)
              : null;
        });
      }
    } catch (_) {}
  }

  BoxDecoration _btnDecoration() {
    if (widget.lightOnGradient) {
      return BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      );
    }
    return BoxDecoration(
      color: context.surfColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.borderColor),
    );
  }

  Color _iconColor() =>
      widget.lightOnGradient ? Colors.white : context.textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
            await _load();
            widget.onChanged?.call();
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: _btnDecoration(),
                child: Icon(Icons.notifications_outlined,
                    color: _iconColor(), size: 22),
              ),
              if (_unread > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBBF24),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      _unread > 9 ? '9+' : '$_unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1E1B2E),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            final role = await _api.getRole();
            if (!mounted) return;
            if (role == 'kind') {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const KindProfileScreen()),
              );
            } else {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            }
            await _load();
            widget.onChanged?.call();
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: (_photoUrl == null && !widget.lightOnGradient)
                  ? AppGradients.primaryButton
                  : null,
              color: widget.lightOnGradient
                  ? Colors.white.withOpacity(0.2)
                  : (_photoUrl != null ? null : null),
              borderRadius: BorderRadius.circular(14),
              border: widget.lightOnGradient
                  ? Border.all(color: Colors.white.withOpacity(0.35))
                  : null,
              image: _photoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(_photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: _photoUrl != null
                ? null
                : Text(
                    _initial,
                    style: TextStyle(
                      color:
                          widget.lightOnGradient ? Colors.white : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
