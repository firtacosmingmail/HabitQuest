import 'ad_config.dart';
import 'ad_service.dart';

/// Web (and any platform without dart:io): no ads.
AdService createPlatformAdService(AdConfig config) => const NoopAdService();
