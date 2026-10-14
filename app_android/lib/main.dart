import 'package:mmcal_core/mmcal_core.dart';

import 'services/admob_service.dart';
import 'widgets/admob_banner.dart';

/// Android entry point: the shared MMCal app plus the AdMob banner.
void main() => runMmCalApp(
      onStartup: AdMobService.initialize,
      bannerBuilder: (_) => const AdMobBanner(),
    );
