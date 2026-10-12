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
