/// Every name shared between the Dart widget bridge and the native
/// home-screen widgets (Android: `android/`, iOS: the WidgetKit extension).
///
/// The native code must use exactly these values; see `docs/WIDGETS.md` for
/// the snapshot schema and the interaction contract.
library;

abstract final class WidgetConstants {
  // Storage ------------------------------------------------------------------

  /// iOS App Group shared by Runner and the widget extension. On Android
  /// home_widget stores everything in the `HomeWidgetPreferences`
  /// SharedPreferences file instead (no group needed).
  static const appGroupId = 'group.com.vvs.habitquest';

  /// Android SharedPreferences file home_widget writes to (read it with
  /// `HomeWidgetPlugin.getData(context)` or this name).
  static const androidPreferencesName = 'HomeWidgetPreferences';

  /// Key of the snapshot: ONE JSON string (schema in `docs/WIDGETS.md`).
  static const snapshotKey = 'hq_widget_snapshot';

  /// Key of the queued widget check-offs: a JSON list written by the
  /// background callback and applied by the app (see `docs/WIDGETS.md`).
  /// Native code never needs to touch it.
  static const toggleQueueKey = 'hq_widget_toggle_queue';

  /// Version of the snapshot JSON. Bumped on breaking schema changes.
  static const snapshotSchemaVersion = 1;

  // Snapshot states ------------------------------------------------------------

  /// Signed in, at least one habit due today.
  static const stateOk = 'ok';

  /// Signed out: show an "Open HabitQuest" prompt.
  static const stateSignedOut = 'signedOut';

  /// Signed in but nothing is due today: show an "Open HabitQuest" prompt.
  static const stateNoHabits = 'noHabits';

  // Android ------------------------------------------------------------------

  /// Fully qualified class names of the Android `AppWidgetProvider`s (e.g.
  /// Glance `GlanceAppWidgetReceiver` subclasses) the app refreshes.
  static const androidTodayHabitsProvider =
      'com.vvs.habitquest.widgets.TodayHabitsWidgetReceiver';
  static const androidDailyQuoteProvider =
      'com.vvs.habitquest.widgets.DailyQuoteWidgetReceiver';

  static const androidProviders = [
    androidTodayHabitsProvider,
    androidDailyQuoteProvider,
  ];

  // iOS ------------------------------------------------------------------------

  /// WidgetKit `kind` strings of the iOS widgets the app reloads.
  static const iosTodayHabitsKind = 'TodayHabitsWidget';
  static const iosDailyQuoteKind = 'DailyQuoteWidget';

  static const iosKinds = [iosTodayHabitsKind, iosDailyQuoteKind];

  // URIs -----------------------------------------------------------------------

  static const urlScheme = 'habitquest';

  /// Host of every widget interaction URI.
  static const widgetHost = 'widget';

  /// Path of the check-off action under [widgetHost].
  static const togglePath = '/toggle';

  /// Query parameter carrying the habit id.
  static const habitIdParam = 'habitId';

  /// Interactive check-off (background callback; also accepted when it
  /// opens the app). Append the habit id (URI-encoded).
  static const toggleUriPrefix = 'habitquest://widget/toggle?habitId=';

  /// Opens the Quotes screen.
  static const quotesUri = 'habitquest://quotes';

  /// Opens the app on the Habits tab.
  static const openUri = 'habitquest://open';

  /// Host of [quotesUri].
  static const quotesHost = 'quotes';

  /// Host of [openUri].
  static const openHost = 'open';

  /// The toggle URI for [habitId].
  static String toggleUri(String habitId) =>
      '$toggleUriPrefix${Uri.encodeQueryComponent(habitId)}';

  // In-process signal ---------------------------------------------------------

  /// `IsolateNameServer` port the app registers so a background check-off
  /// can ask the running app to apply the queue at once.
  static const appPortName = 'habitquest.widget_bridge';

  /// Message (first element of a `[refreshSignal, SendPort]` list) the
  /// background refresh sends on [appPortName]: "the app is alive, refresh
  /// the snapshot yourself". The app answers `true` on the SendPort.
  static const refreshSignal = 'refresh';

  // Background refresh ---------------------------------------------------------

  /// Path of the daily refresh under [widgetHost]. Android's
  /// `WidgetRefreshWorker` (WorkManager) sends [refreshUri] through
  /// home_widget's background receiver; the Dart interactive callback then
  /// rolls the snapshot over and fetches today's quote. It never opens the
  /// app.
  static const refreshPath = '/refresh';

  static const refreshUri = 'habitquest://widget/refresh';

  /// Query parameter of [refreshUri]: the worker's request id, echoed in
  /// [refreshStatusKey] so the worker knows the outcome (and can retry).
  static const refreshIdParam = 'id';

  /// Key where Dart writes `{"id": ..., "outcome": ...}` when a background
  /// refresh finished (`WidgetRefreshOutcome.name`, or `delegated` when the
  /// running app took over). Native code only reads it.
  static const refreshStatusKey = 'hq_widget_refresh_status';
}
