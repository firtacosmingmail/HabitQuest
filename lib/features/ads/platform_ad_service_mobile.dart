import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ad_placement.dart';
import 'ad_service.dart';
import 'ad_slot.dart';

/// iOS/Android get AdMob unless ads are disabled; desktop hosts (including
/// `flutter test`) get the no-op.
AdService createPlatformAdService(AdConfig config) {
  if (!config.enabled) return const NoopAdService();
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return const NoopAdService();
  }
  if (!Platform.isIOS && !Platform.isAndroid) return const NoopAdService();
  return GoogleAdService(config, ios: Platform.isIOS);
}

/// AdMob banners behind Google UMP consent and, on iOS, App Tracking
/// Transparency.
class GoogleAdService implements AdService {
  final AdConfig config;
  final bool ios;

  GoogleAdService(this.config, {required this.ios});

  final _request = Completer<AdRequest?>();
  Future<void>? _init;

  /// The request every banner uses, once consent is settled; null when ads
  /// may not be requested at all.
  Future<AdRequest?> get adRequest => _request.future;

  @override
  Future<void> initialize() => _init ??= _run();

  Future<void> _run() async {
    AdRequest? request;
    try {
      request = await _consentThenStart();
    } on Object catch (e) {
      debugPrint('Ads: initialisation failed, no ads this session: $e');
    }
    if (!_request.isCompleted) _request.complete(request);
  }

  Future<AdRequest?> _consentThenStart() async {
    final consent = ConsentInformation.instance;
    // 1. Google UMP: refresh the consent requirement (EU/UK GDPR, US state
    //    laws) and show the form when it is required.
    final updated = Completer<void>();
    consent.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => updated.complete(),
      (error) {
        debugPrint('Ads: consent info update failed: ${error.message}');
        updated.complete();
      },
    );
    await updated.future;
    final dismissed = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error != null) debugPrint('Ads: consent form: ${error.message}');
      if (!dismissed.isCompleted) dismissed.complete();
    });
    await dismissed.future;
    // A previous session's consent still counts if the update failed.
    if (!await consent.canRequestAds()) return null;

    // EU users who decline get limited/non-personalised ads: the SDK reads
    // the IAB TCF string UMP stored. An unresolved status also stays
    // non-personalised.
    final status = await consent.getConsentStatus();
    var personalised =
        status == ConsentStatus.obtained || status == ConsentStatus.notRequired;

    // 2. iOS App Tracking Transparency, after UMP.
    if (ios) {
      var att = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (att == TrackingStatus.notDetermined) {
        att = await AppTrackingTransparency.requestTrackingAuthorization();
      }
      if (att != TrackingStatus.authorized) personalised = false;
    }

    // 3. Only now start the SDK; no ad was requested before this point.
    await MobileAds.instance.initialize();
    return AdRequest(nonPersonalizedAds: !personalised);
  }

  @override
  Widget buildAd(BuildContext context, AdPlacement placement) => _BannerSlot(
    key: ValueKey('ad-slot-${placement.name}'),
    service: this,
    placement: placement,
  );
}

/// Loads one banner the first time it is laid out (so list ads off screen
/// load only when scrolled to) and shows nothing until it has loaded, so a
/// failed or missing ad collapses to zero height.
class _BannerSlot extends StatefulWidget {
  final GoogleAdService service;
  final AdPlacement placement;

  const _BannerSlot({
    super.key,
    required this.service,
    required this.placement,
  });

  @override
  State<_BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<_BannerSlot>
    with AutomaticKeepAliveClientMixin {
  BannerAd? _ad;
  AdSize? _size;
  bool _started = false;

  @override
  bool get wantKeepAlive => _size != null;

  Future<void> _load(int width) async {
    final request = await widget.service.adRequest;
    if (request == null || !mounted) return;
    final AdSize size = switch (widget.placement) {
      // A small inline banner between habit cards.
      AdPlacement.habitsList => AdSize.getInlineAdaptiveBannerAdSize(
        width,
        100,
      ),
      // Medium rectangle under the calendar when it fits.
      AdPlacement.habitDetails =>
        width >= AdSize.mediumRectangle.width
            ? AdSize.mediumRectangle
            : AdSize.getInlineAdaptiveBannerAdSize(width, 250),
    };
    final ad = BannerAd(
      size: size,
      adUnitId: widget.service.config.unitId(
        widget.placement,
        ios: widget.service.ios,
      ),
      request: request,
      listener: BannerAdListener(
        onAdLoaded: (ad) async {
          final actual = await (ad as BannerAd).getPlatformAdSize();
          if (!mounted) return;
          setState(() => _size = actual ?? size);
          updateKeepAlive();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Ads: ${widget.placement.name} failed: ${error.message}');
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_started && constraints.maxWidth.isFinite) {
          final width = AdFrame.contentWidth(constraints.maxWidth).floor();
          if (width >= 120) {
            _started = true;
            unawaited(_load(width));
          }
        }
        final ad = _ad;
        final size = _size;
        if (ad == null || size == null) return const SizedBox.shrink();
        return AdFrame(
          child: SizedBox(
            width: size.width.toDouble(),
            height: size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
        );
      },
    );
  }
}
