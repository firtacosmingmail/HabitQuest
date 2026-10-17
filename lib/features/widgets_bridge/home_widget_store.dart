import 'dart:developer' as developer;

import 'package:home_widget/home_widget.dart';

import 'widget_constants.dart';
import 'widget_store.dart';

/// [WidgetStore] over home_widget: App Group `UserDefaults` on iOS (call
/// [HomeWidget.setAppGroupId] first), `HomeWidgetPreferences` on Android.
///
/// Only imported on io platforms (see `platform_widget_bridge.dart`).
class HomeWidgetStore implements WidgetStore {
  const HomeWidgetStore();

  @override
  Future<String?> read(String key) => HomeWidget.getWidgetData<String>(key);

  @override
  Future<void> write(String key, String? value) =>
      HomeWidget.saveWidgetData<String>(key, value);

  /// Refreshes every widget; a widget that does not exist (yet) is skipped.
  @override
  Future<void> refreshWidgets() async {
    for (var i = 0; i < WidgetConstants.androidProviders.length; i++) {
      try {
        await HomeWidget.updateWidget(
          qualifiedAndroidName: WidgetConstants.androidProviders[i],
          iOSName: WidgetConstants.iosKinds[i],
        );
      } on Object catch (e) {
        developer.log('Widget refresh skipped: $e', name: 'WidgetBridge');
      }
    }
  }
}
