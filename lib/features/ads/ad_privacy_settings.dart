import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ad_service.dart';

/// The Settings section for ad consent: "Ad privacy choices" re-opens the
/// Google UMP privacy options form when UMP requires an entry point (EEA/UK,
/// regulated US states). Debug builds also get "Reset ad consent". Renders
/// nothing when neither applies (web, tests, ads disabled, other regions).
class AdPrivacySettings extends ConsumerWidget {
  /// Shows the debug reset tile; only ever true outside release builds.
  final bool showDebugReset;

  const AdPrivacySettings({super.key, this.showDebugReset = !kReleaseMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(adServiceProvider);
    final required =
        ref.watch(adPrivacyOptionsRequiredProvider).value ?? false;
    final debugReset = !kReleaseMode && showDebugReset && service.managesConsent;
    if (!required && !debugReset) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ads & privacy', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                if (required)
                  ListTile(
                    key: const ValueKey('settings-ad-privacy'),
                    leading: const Text('🛡️', style: TextStyle(fontSize: 24)),
                    title: const Text('Ad privacy choices'),
                    subtitle: const Text('Change your ad consent choices'),
                    onTap: () => service.showPrivacyOptions(),
                  ),
                if (debugReset)
                  ListTile(
                    key: const ValueKey('settings-ad-consent-reset'),
                    leading: const Text('🧪', style: TextStyle(fontSize: 24)),
                    title: const Text('Reset ad consent (debug)'),
                    subtitle: const Text(
                      'Forgets the consent choice; restart the app to see '
                      'the form again',
                    ),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await service.resetConsent();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Ad consent reset. Restart the app to see the '
                            'form.',
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
