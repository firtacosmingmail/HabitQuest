/// Where the backend lives, read from `--dart-define`s exactly like the
/// mobile app (copied from lib/core/config/backend_config.dart and
/// lib/core/config/env.dart; keep the URL and the anon key in sync):
///
/// ```sh
/// flutter run -d chrome                                   # live project
/// flutter run -d chrome --dart-define-from-file=../env/dev.json
/// flutter run -d chrome --dart-define=ADMIN_DEMO=true     # fake data
/// ```
///
/// Only the public anon key belongs here. The service-role key never goes in
/// the web client: every privileged read/write goes through the admin Edge
/// Functions, which check the admin on the server.
library;

// Copied from lib/core/config/env.dart (the public anon key ships in every
// client by design).
const _liveUrl = 'https://fwikodmrfoorbstmkedx.supabase.co';
const _liveAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ3aWtvZG1yZm9vcmJzdG1rZWR4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzNTU4MTksImV4cCI6MjEwNjkzMTgxOX0.Wl8xd9HPesOxihNhfffcnG2NW-tJ2tGuFyVGdaV6nsg';

class AdminConfig {
  /// Base project URL, without a trailing slash.
  final String supabaseUrl;

  /// The public anon key, sent as `apikey` on every request.
  final String anonKey;

  /// Run against the in-memory demo API (no backend needed).
  final bool demo;

  const AdminConfig({
    required this.supabaseUrl,
    required this.anonKey,
    this.demo = false,
  });

  /// Defaults to the live project; non-empty overrides win.
  factory AdminConfig.resolve({
    String urlOverride = '',
    String anonKeyOverride = '',
    String demoDefine = '',
  }) => AdminConfig(
    supabaseUrl: urlOverride.trim().isNotEmpty ? urlOverride.trim() : _liveUrl,
    anonKey: anonKeyOverride.trim().isNotEmpty
        ? anonKeyOverride.trim()
        : _liveAnonKey,
    demo: demoDefine.trim().toLowerCase() == 'true',
  );

  /// Reads `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `ADMIN_DEMO`.
  factory AdminConfig.fromEnvironment() => AdminConfig.resolve(
    urlOverride: const String.fromEnvironment('SUPABASE_URL'),
    anonKeyOverride: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    demoDefine: const String.fromEnvironment('ADMIN_DEMO'),
  );

  bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  /// URI of an Edge Function, e.g. `function('admin-stats', path: ['me'])`.
  Uri function(
    String name, {
    List<String> path = const [],
    Map<String, String>? query,
  }) {
    var base = supabaseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final root = Uri.parse('$base/functions/v1');
    return root.replace(
      pathSegments: [...root.pathSegments, name, ...path],
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }
}
