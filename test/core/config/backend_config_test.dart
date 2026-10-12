import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/config/backend_config.dart';

const _envs = {
  AppEnv.dev: EnvEntry(
    supabaseUrl: 'https://dev.x',
    supabaseAnonKey: 'dev-key',
  ),
  AppEnv.prod: EnvEntry(
    supabaseUrl: 'https://prod.x',
    supabaseAnonKey: 'prod-key',
  ),
};

void main() {
  group('selectAppEnv', () {
    test('explicit ENV wins over the build mode', () {
      expect(selectAppEnv(envDefine: 'dev', isRelease: true), AppEnv.dev);
      expect(selectAppEnv(envDefine: 'prod', isRelease: false), AppEnv.prod);
      expect(selectAppEnv(envDefine: ' PROD ', isRelease: false), AppEnv.prod);
    });

    test('defaults to prod in release and dev otherwise', () {
      expect(selectAppEnv(envDefine: '', isRelease: true), AppEnv.prod);
      expect(selectAppEnv(envDefine: '', isRelease: false), AppEnv.dev);
      expect(selectAppEnv(envDefine: 'other', isRelease: true), AppEnv.prod);
    });
  });

  group('BackendConfig.resolve', () {
    test('uses the selected env entry when nothing is overridden', () {
      final dev = BackendConfig.resolve(isRelease: false, envs: _envs);
      expect(dev.supabaseUrl, 'https://dev.x');
      expect(dev.anonKey, 'dev-key');

      final prod = BackendConfig.resolve(isRelease: true, envs: _envs);
      expect(prod.supabaseUrl, 'https://prod.x');
      expect(prod.anonKey, 'prod-key');

      final forced = BackendConfig.resolve(
        envDefine: 'prod',
        isRelease: false,
        envs: _envs,
      );
      expect(forced.supabaseUrl, 'https://prod.x');
    });

    test('non-empty overrides win, each independently', () {
      final url = BackendConfig.resolve(
        urlOverride: 'https://other.x',
        isRelease: false,
        envs: _envs,
      );
      expect(url.supabaseUrl, 'https://other.x');
      expect(url.anonKey, 'dev-key');

      final key = BackendConfig.resolve(
        anonKeyOverride: 'other-key',
        isRelease: true,
        envs: _envs,
      );
      expect(key.supabaseUrl, 'https://prod.x');
      expect(key.anonKey, 'other-key');

      final both = BackendConfig.resolve(
        urlOverride: 'https://other.x',
        anonKeyOverride: 'other-key',
        isRelease: false,
        envs: _envs,
      );
      expect(both.supabaseUrl, 'https://other.x');
      expect(both.anonKey, 'other-key');
    });

    test('blank overrides are ignored', () {
      final c = BackendConfig.resolve(
        urlOverride: '  ',
        anonKeyOverride: '',
        isRelease: false,
        envs: _envs,
      );
      expect(c.supabaseUrl, 'https://dev.x');
      expect(c.anonKey, 'dev-key');
    });

    test('isConfigured is false only when an env entry is itself empty', () {
      final c = BackendConfig.resolve(
        isRelease: false,
        envs: const {
          AppEnv.dev: EnvEntry(
            supabaseUrl: 'https://dev.x',
            supabaseAnonKey: '',
          ),
          AppEnv.prod: EnvEntry(supabaseUrl: '', supabaseAnonKey: ''),
        },
      );
      expect(c.isConfigured, isFalse);
    });
  });

  group('built-in config', () {
    test('every env entry is filled in with an anon (public) key', () {
      for (final env in AppEnv.values) {
        final entry = appEnvs[env]!;
        expect(entry.supabaseUrl, startsWith('https://'));
        expect(entry.supabaseAnonKey, isNotEmpty);
        expect(entry.supabaseAnonKey, isNot(contains('service_role')));
        expect(entry.supabaseAnonKey, isNot(startsWith('sb_secret_')));
      }
    });

    test('isConfigured is true by default (no defines)', () {
      expect(BackendConfig.fromEnvironment().isConfigured, isTrue);
      expect(BackendConfig.resolve(isRelease: false).isConfigured, isTrue);
      expect(BackendConfig.resolve(isRelease: true).isConfigured, isTrue);
      expect(
        BackendConfig.fromEnvironment().supabaseUrl,
        BackendConfig.defaultSupabaseUrl,
      );
    });
  });
}
