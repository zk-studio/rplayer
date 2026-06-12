import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String changelog;
  final String downloadUrl;

  AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.changelog,
    required this.downloadUrl,
  });
}

class UpdateService {
  static const String _githubRepo = 'zk-studio/rplayer';

  /// Compares if [latest] is newer than [current] using basic semver rules.
  static bool isVersionNewer(String current, String latest) {
    // Strip leading 'v' or 'V' if present
    String cleanCurrent = current.startsWith(RegExp(r'[vV]')) ? current.substring(1) : current;
    String cleanLatest = latest.startsWith(RegExp(r'[vV]')) ? latest.substring(1) : latest;

    // Remove build numbers/plus suffixes for comparison, e.g. "0.1.0+1" -> "0.1.0"
    cleanCurrent = cleanCurrent.split('+')[0];
    cleanLatest = cleanLatest.split('+')[0];

    final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLength = currentParts.length > latestParts.length ? currentParts.length : latestParts.length;
    for (int i = 0; i < maxLength; i++) {
      final currentVal = i < currentParts.length ? currentParts[i] : 0;
      final latestVal = i < latestParts.length ? latestParts[i] : 0;
      if (latestVal > currentVal) return true;
      if (currentVal > latestVal) return false;
    }
    return false;
  }

  /// Checks if an update is available on GitHub.
  /// Returns [AppUpdateInfo] if a newer version is found, otherwise null.
  static Future<AppUpdateInfo?> checkForUpdates() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final url = Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest');
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'rplayer-updater',
      });

      if (response.statusCode != 200) {
        debugPrint('Failed to query GitHub Releases API: ${response.statusCode}');
        return null;
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final String latestTag = data['tag_name'] ?? '';
      if (latestTag.isEmpty) return null;

      if (!isVersionNewer(currentVersion, latestTag)) {
        return null;
      }

      final String changelog = data['body'] ?? '未提供更新日志。';
      final String releaseHtmlUrl = data['html_url'] ?? 'https://github.com/$_githubRepo/releases';

      // Find the APK file among release assets
      String downloadUrl = releaseHtmlUrl;
      final List<dynamic> assets = data['assets'] ?? [];
      for (final asset in assets) {
        final String name = asset['name'] ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] ?? downloadUrl;
          break;
        }
      }

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestTag,
        changelog: changelog,
        downloadUrl: downloadUrl,
      );
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return null;
    }
  }

  /// Displays the update dialog.
  static void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.system_update_alt_outlined, color: Colors.blueAccent),
              const SizedBox(width: 10),
              Text(
                '发现新版本 (${info.latestVersion})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '当前版本: v${info.currentVersion}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text(
                  '更新内容:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    info.changelog,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('稍后', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDCEEFF),
                foregroundColor: const Color(0xFF0F5A9E),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final uri = Uri.parse(info.downloadUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('无法打开下载链接')),
                    );
                  }
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('立即更新', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
