import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ad_config.dart';
import 'ad_placement.dart';
// Web never sees google_mobile_ads (it imports dart:io): the stub returns a
// no-op service there; on the Dart VM the mobile factory picks per platform.
import 'platform_ad_service_stub.dart'
    if (dart.library.io) 'platform_ad_service_mobile.dart';

/// Shows ads in [AdPlacement]s. The app only talks to this interface:
/// `GoogleAdService` (iOS/Android) serves AdMob banners, [NoopAdService]
/// (web, tests, ads disabled) renders nothing, and widget tests override
/// [adServiceProvider] with a fake that renders a placeholder.
abstract class AdService {
  /// Runs consent (UMP, then App Tracking Transparency on iOS) and starts the
  /// ads SDK. Called once at app start by `AdsBootstrap`; no ad is requested
  /// before it completes. Safe to call more than once.
  Future<void> initialize();

  /// The ad for [placement], or an empty widget when there is none (no
  /// consent, not loaded yet, failed to load). The visible ad is wrapped in
  /// an `AdFrame` (narrower than the habit cards, rounded, labelled "Ad").
  Widget buildAd(BuildContext context, AdPlacement placement);
}

/// Renders nothing and requests nothing.
class NoopAdService implements AdService {
  const NoopAdService();

  @override
  Future<void> initialize() async {}

  @override
  Widget buildAd(BuildContext context, AdPlacement placement) =>
      const SizedBox.shrink();
}

/// The ad service for this platform; override in tests.
final adServiceProvider = Provider<AdService>(
  (ref) => createPlatformAdService(ref.watch(adConfigProvider)),
);
