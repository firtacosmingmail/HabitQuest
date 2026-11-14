import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ads/ad_privacy_settings.dart';
import '../projects/notifications/project_notification_settings.dart';
import '../projects/notifications/project_notifications_providers.dart';

/// App settings (reached from Profile): the Projects notification toggles
/// and, when Google UMP asks for one, the ad privacy choices entry.
/// Stored on this device only; turning one off cancels its pending
/// notifications at once.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(projectNotificationSettingsProvider);
    final notifier = ref.read(projectNotificationSettingsProvider.notifier);
    final theme = Theme.of(context);

    Widget toggle({
      required String key,
      required String emoji,
      required String title,
      required String subtitle,
      required bool value,
      required ProjectNotificationSettings Function(bool) apply,
    }) => SwitchListTile(
      key: ValueKey(key),
      secondary: Text(emoji, style: const TextStyle(fontSize: 24)),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) => notifier.set(apply(v)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Project notifications', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            kIsWeb
                ? 'Project notifications only fire in the mobile apps.'
                : 'Little nudges to keep your quests on track 🗺️',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                toggle(
                  key: 'settings-work-splits',
                  emoji: '⚔️',
                  title: 'Work split starts',
                  subtitle: 'When a work session begins',
                  value: settings.workSplits,
                  apply: (v) => settings.copyWith(workSplits: v),
                ),
                toggle(
                  key: 'settings-deadlines',
                  emoji: '⏳',
                  title: 'Deadlines',
                  subtitle:
                      '3 days before, 1 day before and on the morning '
                      'of a target\'s deadline',
                  value: settings.deadlines,
                  apply: (v) => settings.copyWith(deadlines: v),
                ),
                toggle(
                  key: 'settings-task-deliveries',
                  emoji: '📦',
                  title: 'Task deliveries',
                  subtitle: 'The morning before a plan task is due',
                  value: settings.taskDeliveries,
                  apply: (v) => settings.copyWith(taskDeliveries: v),
                ),
              ],
            ),
          ),
          const AdPrivacySettings(),
        ],
      ),
    );
  }
}
