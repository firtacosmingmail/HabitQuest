import 'package:flutter/foundation.dart' show kReleaseMode;

/// The region the UMP SDK pretends the device is in, for consent testing.
enum ConsentDebugGeography {
  /// No override: UMP uses the real location.
  none,

  /// European Economic Area / UK / Switzerland (the GDPR message).
  eea,

  /// A regulated US state (the US state regulations message).
  regulatedUsState,

  /// A region with no regulation in force (no message).
  other,
}

/// Debug-only overrides for Google UMP consent testing, read from
/// `--dart-define`s:
///
/// - `ADS_CONSENT_DEBUG_GEOGRAPHY=eea|us|other`: pretend the device is there.
/// - `ADS_CONSENT_TEST_DEVICE_ID=<hashed id>[,<hashed id>]`: the device(s)
///   the debug geography applies to (UMP ignores it on other devices). The
///   hashed id is in logcat / the Xcode console, see docs/ADMOB_CONSENT.md.
/// - `ADS_CONSENT_RESET=true`: forget the stored consent at app start, so the
///   form shows again.
///
/// Release builds always get [ConsentDebugConfig.off], whatever the defines
/// say: [resolve] checks `isRelease` first, and [fromEnvironment] passes
/// `kReleaseMode`.
class ConsentDebugConfig {
  final ConsentDebugGeography geography;
  final List<String> testDeviceIds;
  final bool resetOnStart;

  const ConsentDebugConfig({
    this.geography = ConsentDebugGeography.none,
    this.testDeviceIds = const [],
    this.resetOnStart = false,
  });

  /// No debug overrides (every release build).
  static const off = ConsentDebugConfig();

  /// True when UMP should get a `ConsentDebugSettings`.
  bool get hasDebugSettings =>
      geography != ConsentDebugGeography.none || testDeviceIds.isNotEmpty;

  /// True when any debug override is active.
  bool get isActive => hasDebugSettings || resetOnStart;

  /// Pure resolution from raw define values; unknown values are ignored.
  factory ConsentDebugConfig.resolve({
    String geographyDefine = '',
    String testDeviceIdDefine = '',
    String resetDefine = '',
    required bool isRelease,
  }) {
    if (isRelease) return off;
    final geography = switch (geographyDefine.trim().toLowerCase()) {
      'eea' || 'eu' || 'gdpr' => ConsentDebugGeography.eea,
      'us' ||
      'us_state' ||
      'regulated_us_state' ||
      'regulatedusstate' => ConsentDebugGeography.regulatedUsState,
      'other' || 'none_regulated' => ConsentDebugGeography.other,
      _ => ConsentDebugGeography.none,
    };
    final ids = [
      for (final id in testDeviceIdDefine.split(','))
        if (id.trim().isNotEmpty) id.trim(),
    ];
    final reset = const {
      'true',
      '1',
      'yes',
      'on',
    }.contains(resetDefine.trim().toLowerCase());
    return ConsentDebugConfig(
      geography: geography,
      testDeviceIds: List.unmodifiable(ids),
      resetOnStart: reset,
    );
  }

  /// Reads the `ADS_CONSENT_*` dart-defines; always [off] in release builds.
  factory ConsentDebugConfig.fromEnvironment() => ConsentDebugConfig.resolve(
    geographyDefine: const String.fromEnvironment('ADS_CONSENT_DEBUG_GEOGRAPHY'),
    testDeviceIdDefine: const String.fromEnvironment(
      'ADS_CONSENT_TEST_DEVICE_ID',
    ),
    resetDefine: const String.fromEnvironment('ADS_CONSENT_RESET'),
    isRelease: kReleaseMode,
  );
}
