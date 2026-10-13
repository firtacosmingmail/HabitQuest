// Per-environment backend settings. THIS is the one place to edit when the
// dev or prod Supabase project changes.
//
// Only the public anon key belongs here: it ships in every client by design
// (row-level security and the Edge Functions protect the data). Never put the
// service_role / secret key or any other secret in this file.

/// Which built-in backend environment the app uses.
enum AppEnv { dev, prod }

/// Backend settings for one [AppEnv].
class EnvEntry {
  final String supabaseUrl;
  final String supabaseAnonKey;

  const EnvEntry({required this.supabaseUrl, required this.supabaseAnonKey});
}

const _liveUrl = 'https://fwikodmrfoorbstmkedx.supabase.co';
const _liveAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ3aWtvZG1yZm9vcmJzdG1rZWR4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzNTU4MTksImV4cCI6MjEwNjkzMTgxOX0.Wl8xd9HPesOxihNhfffcnG2NW-tJ2tGuFyVGdaV6nsg';

/// Built-in settings per environment. For now dev and prod share one project.
const Map<AppEnv, EnvEntry> appEnvs = {
  AppEnv.dev: EnvEntry(supabaseUrl: _liveUrl, supabaseAnonKey: _liveAnonKey),
  AppEnv.prod: EnvEntry(supabaseUrl: _liveUrl, supabaseAnonKey: _liveAnonKey),
};

// ---------------------------------------------------------------------------
// Advertising (Google AdMob). THIS is the one place to edit the AdMob IDs.
//
// Every ID below defaults to Google's official TEST IDs, which always serve
// test ads and are safe to click. Replace them with the IDs from your AdMob
// console (Apps > App settings for the app IDs, Apps > Ad units for the unit
// IDs) before releasing. Each unit ID can also be overridden per build with a
// --dart-define (see AdConfig in lib/features/ads/ad_config.dart):
//
//   ADS_ENABLED=false                       turn ads off entirely
//   ADMOB_IOS_HABITS_LIST_UNIT_ID=...       ADMOB_ANDROID_HABITS_LIST_UNIT_ID=...
//   ADMOB_IOS_HABIT_DETAILS_UNIT_ID=...     ADMOB_ANDROID_HABIT_DETAILS_UNIT_ID=...
//
// The *app* IDs are read by the native SDKs before any Dart code runs, so they
// must ALSO be set natively: GADApplicationIdentifier in ios/Runner/Info.plist
// and com.google.android.gms.ads.APPLICATION_ID in
// android/app/src/main/AndroidManifest.xml. They are kept here so all AdMob
// IDs are listed in one place; keep the three in sync.
// ---------------------------------------------------------------------------

/// AdMob app and ad unit IDs for one [AppEnv].
class AdMobIds {
  final String iosAppId;
  final String androidAppId;

  /// Banner unit shown inline in the Habits list.
  final String iosHabitsListUnitId;
  final String androidHabitsListUnitId;

  /// Banner unit shown under the calendar on the habit details screen.
  final String iosHabitDetailsUnitId;
  final String androidHabitDetailsUnitId;

  const AdMobIds({
    required this.iosAppId,
    required this.androidAppId,
    required this.iosHabitsListUnitId,
    required this.androidHabitsListUnitId,
    required this.iosHabitDetailsUnitId,
    required this.androidHabitDetailsUnitId,
  });
}

/// Google's official sample IDs (always serve test ads).
/// https://developers.google.com/admob/ios/test-ads and
/// https://developers.google.com/admob/android/test-ads
const admobTestIds = AdMobIds(
  iosAppId: 'ca-app-pub-3940256099942544~1458002511',
  androidAppId: 'ca-app-pub-3940256099942544~3347511713',
  iosHabitsListUnitId: 'ca-app-pub-3940256099942544/2934735716',
  androidHabitsListUnitId: 'ca-app-pub-3940256099942544/6300978111',
  iosHabitDetailsUnitId: 'ca-app-pub-3940256099942544/2934735716',
  androidHabitDetailsUnitId: 'ca-app-pub-3940256099942544/6300978111',
);

/// AdMob IDs per environment. Swap prod (and dev, if you want real ads in
/// debug builds; Google recommends test ads during development) for your own.
const Map<AppEnv, AdMobIds> admobEnvs = {
  AppEnv.dev: admobTestIds,
  AppEnv.prod: admobTestIds,
};

// ---------------------------------------------------------------------------
// Sign in with Google & Apple. THIS is the one place to put the OAuth client
// IDs (see "Sign in with Google & Apple" in the README for how to create them).
//
// >>> PLACEHOLDERS: every value below is EMPTY until you supply it. <<<
// While a value is empty the matching button is hidden (debug builds show a
// small "not configured" hint instead). Client IDs are public identifiers,
// not secrets; the Google client SECRET and the Apple key (.p8) go ONLY into
// the Supabase dashboard, never here.
//
// Each value can be overridden per build with a --dart-define:
//
//   GOOGLE_IOS_CLIENT_ID=1234-abc.apps.googleusercontent.com
//   GOOGLE_WEB_CLIENT_ID=1234-xyz.apps.googleusercontent.com
//   APPLE_SERVICE_ID=com.habitquest.signin
//   APPLE_REDIRECT_URI=https://<your-site>/apple-callback
//
// The iOS client ID must ALSO be added natively, reversed, as a URL scheme in
// ios/Runner/Info.plist (CFBundleURLSchemes, the "com.googleusercontent.apps."
// placeholder entry); keep the two in sync.
// ---------------------------------------------------------------------------

/// OAuth client IDs for one [AppEnv].
class OAuthIds {
  /// Google Cloud "iOS" OAuth client ID (used by google_sign_in on iOS).
  final String googleIosClientId;

  /// Google Cloud "Web application" OAuth client ID. Used on web, and as the
  /// Android `serverClientId` so the ID token's audience is this client.
  final String googleWebClientId;

  /// Apple Services ID, for Apple's web flow on Android and web only (iOS
  /// and macOS use the native flow with the app's bundle ID).
  final String appleServiceId;

  /// Return URL registered on the Services ID for the web flow.
  final String appleRedirectUri;

  const OAuthIds({
    this.googleIosClientId = '',
    this.googleWebClientId = '',
    this.appleServiceId = '',
    this.appleRedirectUri = '',
  });
}

/// OAuth IDs: the Google web client is set (it is the client configured in
/// the Supabase Google provider); the others are still empty placeholders.
const oauthPlaceholderIds = OAuthIds(
  googleIosClientId:
      '', // TODO(you): <number>-<id>.apps.googleusercontent.com (iOS client)
  // Web client (also the Android serverClientId); matches Supabase's
  // external_google_client_id.
  googleWebClientId:
      '1004491055558-ki4qtpcukb7l3859khfs7kla2h9s6ric.apps.googleusercontent.com',
  appleServiceId:
      '', // TODO(you): e.g. com.habitquest.signin (only for Android/web)
  appleRedirectUri:
      '', // TODO(you): Services ID return URL (only for Android/web)
);

/// OAuth IDs per environment (dev and prod share the one Supabase project).
const Map<AppEnv, OAuthIds> oauthEnvs = {
  AppEnv.dev: oauthPlaceholderIds,
  AppEnv.prod: oauthPlaceholderIds,
};

/// Picks the environment: an explicit `ENV=dev|prod` define wins (case
/// insensitive); otherwise prod in release builds and dev in debug/profile.
AppEnv selectAppEnv({required String envDefine, required bool isRelease}) {
  switch (envDefine.trim().toLowerCase()) {
    case 'dev':
      return AppEnv.dev;
    case 'prod':
      return AppEnv.prod;
    default:
      return isRelease ? AppEnv.prod : AppEnv.dev;
  }
}
