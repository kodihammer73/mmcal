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

  Future<void> _openStore(BuildContext context) async {
    final uri = Uri.parse(result.updateUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
