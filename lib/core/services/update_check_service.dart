import 'package:flutter/material.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:semplanner/core/router.dart';

/// Checks Firebase Remote Config for a minimum required version.
/// If the current app version is older, shows a mandatory update dialog.
///
/// Setup in Firebase Console:
///   Remote Config → Add Parameter:
///     key:          minimum_version
///     default value: 1.0.0
///
/// To force-update all old beta users to your new ads version:
///   Change minimum_version to "1.0.1" (or whatever your new version is).
class UpdateCheckService {
  UpdateCheckService._();
  static final UpdateCheckService instance = UpdateCheckService._();

  // Play Store link - update once your app is live.
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.student.semplanner.semplanner';

  // Fallback APK download link from your GitHub site.
  static const String _apkUrl =
      'https://kitretsu2809.github.io/semPlanner/semplanner.apk';

  Future<void> checkAndEnforceUpdate() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ));

      // Set default so app works offline
      await remoteConfig.setDefaults({'minimum_version': '1.0.0'});
      await remoteConfig.fetchAndActivate();

      final minVersion = remoteConfig.getString('minimum_version');
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_isUpdateRequired(currentVersion, minVersion)) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          _showUpdateDialog(context);
        }
      }
    } catch (e) {
      print("Update check error: $e");
      // Fail silently — never block the user due to a network error.
    }
  }

  /// Returns true if currentVersion < minimumVersion
  bool _isUpdateRequired(String current, String minimum) {
    final c = current.split('.').map(int.tryParse).toList();
    final m = minimum.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final cv = (i < c.length ? c[i] : 0) ?? 0;
      final mv = (i < m.length ? m[i] : 0) ?? 0;
      if (cv < mv) return true;
      if (cv > mv) return false;
    }
    return false;
  }

  void _showUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // Cannot dismiss
      builder: (_) => PopScope(
        canPop: false, // Cannot press back
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.system_update_rounded, color: Color(0xFF007AFF), size: 28),
              SizedBox(width: 10),
              Text('Update Required'),
            ],
          ),
          content: const Text(
            'A new version of semPlanner is available with exciting new features!\n\n'
            'Please update to continue using the app.',
          ),
          actions: [
            TextButton(
              onPressed: () => launchUrl(Uri.parse(_apkUrl)),
              child: const Text('Download APK'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => launchUrl(
                Uri.parse(_playStoreUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Update on Play Store'),
            ),
          ],
        ),
      ),
    );
  }
}
