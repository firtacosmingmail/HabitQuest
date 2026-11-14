import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/features/projects/notifications/project_notification_settings.dart';
import 'package:habit_quest/features/projects/notifications/project_notifications_providers.dart';

import '../../helpers/test_app.dart';

void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('three toggles, default on, stored locally', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = ProjectNotificationSettingsStore(MemoryStringStore());
    final changes = <ProjectNotificationSettings>[];
    store.changes.listen(changes.add);

    await pumpHabitQuestApp(
      tester,
      initialLocation: '/profile/settings',
      overrides: [
        projectNotificationSettingsStoreProvider.overrideWithValue(store),
      ],
    );

    expect(find.text('Settings'), findsOneWidget);
    for (final k in [
      'settings-work-splits',
      'settings-deadlines',
      'settings-task-deliveries',
    ]) {
      expect(tester.widget<SwitchListTile>(key(k)).value, isTrue);
    }

    await tester.tap(key('settings-deadlines'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(key('settings-deadlines')).value,
        isFalse);
    expect(store.value,
        ProjectNotificationSettings.allOn.copyWith(deadlines: false));
    expect(changes, hasLength(1));
  });

  testWidgets('reached from Profile', (tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHabitQuestApp(tester, initialLocation: '/profile');
    await tester.scrollUntilVisible(key('profile-settings'), 200);
    await tester.tap(key('profile-settings'));
    await tester.pumpAndSettle();
    expect(key('settings-work-splits'), findsOneWidget);
  });
}
