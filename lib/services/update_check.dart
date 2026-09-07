import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result of a remote update check.
class UpdateCheckResult {
  /// Whether the installed version is below the required minimum.
  final bool updateRequired;

  /// The minimum version required to keep using the app (e.g. "1.1.0").
  final String minVersion;

  /// The installed version (e.g. "1.0.0").
  final String installedVersion;

  /// URL to open so the user can update (store page or direct APK).
  final String updateUrl;

  /// Optional message shown on the blocking screen.
  final String message;

  const UpdateCheckResult({
    required this.updateRequired,
    required this.minVersion,
    required this.installedVersion,
    required this.updateUrl,
    required this.message,
  });
}

/// Performs a remote "forced update" check.
///
/// The app fetches a small JSON file hosted at [configUrl]. The file controls
/// the minimum version users must be on. Example JSON:
///
/// ```json
/// {
///   "min_version": "1.1.0",
///   "update_url": "https://play.google.com/store/apps/details?id=com.mmcal.app",
///   "message": "A new version is required to continue using MMCal."
/// }
/// ```
///
/// If the installed version is lower than [min_version], [updateRequired]
/// is true and the caller should show a blocking update screen.
class UpdateChecker {
  /// The URL of the hosted JSON config (mmcal_version.json on the project
  /// website). The file controls the minimum app version and the store link.
  /// It is checked at app launch; a 404/network error fails open (no force).
  /// https://www.gurdwarasahibmelaka.com/policy/mmcal_version.json
  static const String configUrl =
      'https://www.gurdwarasahibmelaka.com/policy/mmcal_version.json';

  /// Timeout for the network request.
  static const Duration _timeout = Duration(seconds: 8);

  /// Compares two dotted version strings. Returns >0 if [a] > [b],
  /// <0 if [a] < [b], 0 if equal. Handles "1.0", "1.0.0", "1.0.0+1".
  static int compareVersions(String a, String b) {
    // Strip build metadata after '+' (e.g. "1.0.0+1" -> "1.0.0").
    String clean(String v) => v.split('+').first.trim();

    final pa = clean(a).split('.').map(int.tryParse).toList();
    final pb = clean(b).split('.').map(int.tryParse).toList();

    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? (pa[i] ?? 0) : 0;
      final vb = i < pb.length ? (pb[i] ?? 0) : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  /// Fetches the remote config and checks whether an update is required.
  ///
  /// Returns an [UpdateCheckResult]. If the network request fails or the
  /// config is malformed, returns a result with [updateRequired] = false so
  /// the app still works offline (fail-open).
  static Future<UpdateCheckResult> checkForUpdate({
    required String installedVersion,
    String? url,
  }) async {
    final target = url ?? configUrl;
    try {
      final res = await http
          .get(Uri.parse(target))
          .timeout(_timeout);

      if (res.statusCode != 200) {
        return _noUpdate(installedVersion);
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final minVersion = (data['min_version'] as String?)?.trim() ?? '';
      final updateUrl = (data['update_url'] as String?)?.trim() ?? '';
      final message = (data['message'] as String?)?.trim() ??
          'A new version of MMCal is required. Please update to continue.';

      if (minVersion.isEmpty || updateUrl.isEmpty) {
        return _noUpdate(installedVersion);
      }

      final required = compareVersions(installedVersion, minVersion) < 0;

      return UpdateCheckResult(
        updateRequired: required,
        minVersion: minVersion,
        installedVersion: installedVersion,
        updateUrl: updateUrl,
        message: message,
      );
    } catch (_) {
      // Network error / timeout / bad JSON -> allow the app to run.
      return _noUpdate(installedVersion);
    }
  }

  static UpdateCheckResult _noUpdate(String installedVersion) {
    return UpdateCheckResult(
      updateRequired: false,
      minVersion: installedVersion,
      installedVersion: installedVersion,
      updateUrl: '',
      message: '',
    );
  }
}
