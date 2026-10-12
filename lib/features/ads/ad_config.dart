import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import 'ad_placement.dart';

/// The AdMob settings compiled into this build: the [AdMobIds] of the
/// selected [AppEnv] (see `lib/core/config/env.dart`) with any
/// `--dart-define` overrides applied.
class AdConfig {
  /// False turns every ad slot into a no-op (`--dart-define=ADS_ENABLED=false`).
  final bool enabled;
  final AdMobIds ids;

  const AdConfig({required this.enabled, required this.ids});

  /// Pure resolution from raw define values. A non-empty override replaces
  /// the env default for that one unit ID.
  factory AdConfig.resolve({
    String envDefine = '',
    String enabledDefine = '',
    String iosHabitsList = '',
    String androidHabitsList = '',
    String iosHabitDetails = '',
    String androidHabitDetails = '',
    required bool isRelease,
    Map<AppEnv, AdMobIds> envs = admobEnvs,
  }) {
    final base =
        envs[selectAppEnv(envDefine: envDefine, isRelease: isRelease)]!;
    String pick(String override, String fallback) =>
        override.trim().isNotEmpty ? override.trim() : fallback;
    final off = const {'false', '0', 'no', 'off'}
        .contains(enabledDefine.trim().toLowerCase());
    return AdConfig(
      enabled: !off,
      ids: AdMobIds(
        iosAppId: base.iosAppId,
        androidAppId: base.androidAppId,
        iosHabitsListUnitId: pick(iosHabitsList, base.iosHabitsListUnitId),
        androidHabitsListUnitId: pick(
          androidHabitsList,
          base.androidHabitsListUnitId,
        ),
        iosHabitDetailsUnitId: pick(
          iosHabitDetails,
          base.iosHabitDetailsUnitId,
        ),
        androidHabitDetailsUnitId: pick(
          androidHabitDetails,
          base.androidHabitDetailsUnitId,
        ),
      ),
    );
  }

  /// Reads `ENV`, `ADS_ENABLED` and the `ADMOB_*_UNIT_ID` dart-defines.
  factory AdConfig.fromEnvironment() => AdConfig.resolve(
    envDefine: const String.fromEnvironment('ENV'),
    enabledDefine: const String.fromEnvironment('ADS_ENABLED'),
    iosHabitsList: const String.fromEnvironment(
      'ADMOB_IOS_HABITS_LIST_UNIT_ID',
    ),
    androidHabitsList: const String.fromEnvironment(
      'ADMOB_ANDROID_HABITS_LIST_UNIT_ID',
    ),
    iosHabitDetails: const String.fromEnvironment(
      'ADMOB_IOS_HABIT_DETAILS_UNIT_ID',
    ),
    androidHabitDetails: const String.fromEnvironment(
      'ADMOB_ANDROID_HABIT_DETAILS_UNIT_ID',
    ),
    isRelease: kReleaseMode,
  );

  /// The banner unit ID for [placement] on iOS or Android.
  String unitId(AdPlacement placement, {required bool ios}) =>
      switch (placement) {
        AdPlacement.habitsList =>
          ios ? ids.iosHabitsListUnitId : ids.androidHabitsListUnitId,
        AdPlacement.habitDetails =>
          ios ? ids.iosHabitDetailsUnitId : ids.androidHabitDetailsUnitId,
      };
}

/// The AdMob configuration; override in tests.
final adConfigProvider = Provider<AdConfig>((ref) => AdConfig.fromEnvironment());
