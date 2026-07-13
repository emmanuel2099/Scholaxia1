import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_service.dart';
import '../theme/app_theme.dart';

/// Checks the backend for a newer published app build and prompts the user to
/// update. Bump APP_LATEST_BUILD on the server after publishing to the store to
/// trigger the popup; set APP_MIN_SUPPORTED_BUILD to force an update.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  final _api = ApiService();
  bool _checked = false;

  Future<void> checkForUpdate(GlobalKey<NavigatorState> navKey) async {
    if (_checked || kIsWeb) return;
    _checked = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final data = await _api.getAppVersion();
      final latestBuild = (data['latest_build'] as num?)?.toInt() ?? 0;
      final minBuild = (data['min_supported_build'] as num?)?.toInt() ?? 0;
      if (latestBuild <= currentBuild) return; // already up to date

      final force = currentBuild < minBuild;
      final latestVersion = data['latest_version']?.toString() ?? '';
      final message = data['message']?.toString() ??
          'A new version of the app is available.';
      final androidUrl = data['android_url']?.toString() ?? '';
      final iosUrl = data['ios_url']?.toString() ?? '';
      final storeUrl = defaultTargetPlatform == TargetPlatform.iOS
          ? (iosUrl.isNotEmpty ? iosUrl : androidUrl)
          : androidUrl;

      final ctx = navKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      await _showDialog(
        ctx,
        message: message,
        latestVersion: latestVersion,
        storeUrl: storeUrl,
        force: force,
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  Future<void> _showDialog(
    BuildContext context, {
    required String message,
    required String latestVersion,
    required String storeUrl,
    required bool force,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) {
        return PopScope(
          canPop: !force,
          child: AlertDialog(
            backgroundColor: ctx.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.system_update_rounded,
                    color: ctx.accentColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    force ? 'Update required' : 'Update available',
                    style: TextStyle(
                        color: ctx.textColor, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: TextStyle(color: ctx.textColor)),
                if (latestVersion.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Latest version: $latestVersion',
                      style:
                          TextStyle(color: ctx.greyColor, fontSize: 12.5)),
                ],
              ],
            ),
            actions: [
              if (!force)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Later',
                      style: TextStyle(color: ctx.greyColor)),
                ),
              ElevatedButton(
                onPressed: () => _openStore(storeUrl),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ctx.accentColor,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Update now',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openStore(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open store URL: $e');
    }
  }
}
