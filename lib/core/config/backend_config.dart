import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';

export 'env.dart' show AppEnv, EnvEntry, appEnvs, selectAppEnv;

/// Where the Supabase Edge Functions live, read from `--dart-define`s:
///
/// ```sh
/// flutter run --dart-define=SUPABASE_ANON_KEY=eyJ...
/// flutter run --dart-define-from-file=env/dev.json
/// ```
///
/// `SUPABASE_URL` defaults to the project's hosted URL; `SUPABASE_ANON_KEY`
/// has no default, and the app shows a friendly "not configured" message on
/// the login screen until it is provided.
class BackendConfig {
  /// Base project URL, without a trailing slash.
  final String supabaseUrl;

  /// The public anon key, sent as `apikey` on every request.
  final String anonKey;

  const BackendConfig({required this.supabaseUrl, required this.anonKey});

  static const defaultSupabaseUrl = 'https://fwikodmrfoorbstmkedx.supabase.co';

  /// The config compiled into this build.
  /// Pure resolution from raw define values: the env entry chosen by
  /// [envDefine]/[isRelease] (see [selectAppEnv]) supplies the defaults, and
  /// a non-empty [urlOverride] / [anonKeyOverride] replaces each one
  /// independently.
  factory BackendConfig.resolve({
    String envDefine = '',
    String urlOverride = '',
    String anonKeyOverride = '',
    required bool isRelease,
    Map<AppEnv, EnvEntry> envs = appEnvs,
  }) {
    final entry =
        envs[selectAppEnv(envDefine: envDefine, isRelease: isRelease)]!;
    return BackendConfig(
      supabaseUrl: urlOverride.trim().isNotEmpty
          ? urlOverride.trim()
          : entry.supabaseUrl,
      anonKey: anonKeyOverride.trim().isNotEmpty
          ? anonKeyOverride.trim()
          : entry.supabaseAnonKey,
    );
  }

  /// Reads `ENV`, `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the
  /// `--dart-define`s and resolves them with [BackendConfig.resolve].
  factory BackendConfig.fromEnvironment() => BackendConfig.resolve(
    envDefine: const String.fromEnvironment('ENV'),
    urlOverride: const String.fromEnvironment('SUPABASE_URL'),
    anonKeyOverride: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    isRelease: kReleaseMode,
  );

  /// Both the URL and the anon key are present.
  bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  /// `{SUPABASE_URL}/functions/v1`.
  Uri get functionsBaseUri {
    var base = supabaseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base/functions/v1');
  }

  /// URI of an Edge Function, e.g. `function('habits', path: ['batch'])`.
  Uri function(
    String name, {
    List<String> path = const [],
    Map<String, String>? query,
  }) {
    final base = functionsBaseUri;
    return base.replace(
      pathSegments: [...base.pathSegments, name, ...path],
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }
}

/// The backend configuration; override in tests.
final backendConfigProvider = Provider<BackendConfig>(
  (ref) => BackendConfig.fromEnvironment(),
);
