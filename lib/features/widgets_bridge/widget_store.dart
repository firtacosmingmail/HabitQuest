/// The shared storage the widgets read, and the "please redraw" signal.
///
/// The app uses the home_widget implementation (`platform_widget_store_io`:
/// App Group UserDefaults on iOS, `HomeWidgetPreferences` on Android). Tests
/// and web use [MemoryWidgetStore] / nothing at all.
abstract interface class WidgetStore {
  Future<String?> read(String key);

  /// Writes [value] under [key] (`null` removes it).
  Future<void> write(String key, String? value);

  /// Asks every home-screen widget (see `WidgetConstants`) to redraw.
  Future<void> refreshWidgets();
}

/// In-memory [WidgetStore] for tests.
class MemoryWidgetStore implements WidgetStore {
  final Map<String, String> data;

  /// Number of [refreshWidgets] calls.
  int refreshCount = 0;

  MemoryWidgetStore([Map<String, String>? initial]) : data = {...?initial};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> refreshWidgets() async => refreshCount++;
}
