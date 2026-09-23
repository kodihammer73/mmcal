import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_check.dart';

/// A blocking screen shown when a forced update is required.
///
/// The user cannot dismiss or back out of this screen — they must tap
/// "Update Now" (which opens the store page) to continue using the app.
class UpdateRequiredScreen extends StatelessWidget {
  final UpdateCheckResult result;
  const UpdateRequiredScreen({super.key, required this.result});

  /// Opens the store page for the update. On iOS the hosted config may still
  /// carry the Google Play URL (it predates the App Store release), which would
  /// send users to a rival store - never acceptable on iOS.
  ///
  /// iOS App Store product page (App Store Connect -> App Information ->
  /// Apple ID 6809318912). Used when the hosted config's update_url is not an
  /// App Store link, so iOS users are never sent to another store.
  static const String _iosAppStoreUrl =
      'https://apps.apple.com/app/id6809318912';

  static const String _androidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.mmcal.app';

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// The URL to open, or null when no valid store URL exists for this
  /// platform (the UI then shows a manual-update message).
  static String? _storeUrlFor(UpdateCheckResult result) {
    if (_isIOS) {
      if (result.updateUrl.startsWith('https://apps.apple.com/')) {
        return result.updateUrl;
      }
      return _iosAppStoreUrl.isEmpty ? null : _iosAppStoreUrl;
    }
    return result.updateUrl.isEmpty ? _androidStoreUrl : result.updateUrl;
  }

  Future<void> _openStore(BuildContext context) async {
    final url = _storeUrlFor(result);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please update MMCal via the App Store to continue.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the store. Please update manually.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // Block the system back button so the user cannot skip the update.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.system_update_alt,
                    size: 96,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Update Required',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    result.message,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your version: ${result.installedVersion}\n'
                    'Required version: ${result.minVersion}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () => _openStore(context),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Update Now'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
