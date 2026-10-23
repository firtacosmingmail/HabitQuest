/// Widget URIs (`habitquest://widget/toggle?habitId=`, `habitquest://quotes`,
/// `habitquest://open`) → in-app behaviour.
library;

import '../../core/router/app_routes.dart';
import 'widget_constants.dart';

bool _isAppScheme(Uri uri) =>
    uri.scheme.isEmpty || uri.scheme == WidgetConstants.urlScheme;

/// The habit id of a check-off URI, or `null` for any other URI.
String? toggleHabitId(Uri? uri) {
  if (uri == null || !_isAppScheme(uri)) return null;
  if (uri.host != WidgetConstants.widgetHost) return null;
  if (uri.path != WidgetConstants.togglePath) return null;
  final id = uri.queryParameters[WidgetConstants.habitIdParam];
  return (id == null || id.isEmpty) ? null : id;
}

/// Whether [uri] is the background daily refresh
/// (`habitquest://widget/refresh`, sent by Android's `WidgetRefreshWorker`).
bool isWidgetRefreshUri(Uri? uri) =>
    uri != null &&
    _isAppScheme(uri) &&
    uri.host == WidgetConstants.widgetHost &&
    uri.path == WidgetConstants.refreshPath;

/// The in-app location for a widget URI that opened the app (go_router
/// sees the platform deep link with its host), or `null` if [uri] is not a
/// widget URI. A check-off URI lands on the Habits tab (the check-off itself
/// is done by the caller).
///
/// The quotes link maps to the Quotes screen stacked on the Habits tab, never
/// to a stack holding only Quotes: the link is then consumed by this one
/// navigation, Back returns to Habits, and a later launcher start (which on
/// Android 12+ resumes the same activity) shows Habits rather than replaying
/// the Quotes screen.
String? widgetDeepLinkLocation(Uri uri) {
  if (uri.scheme != WidgetConstants.urlScheme && uri.host.isEmpty) {
    return null;
  }
  if (!_isAppScheme(uri)) return null;
  switch (uri.host) {
    case WidgetConstants.quotesHost:
      return uri.path == '/saved'
          ? AppRoutes.habitsSavedQuotes
          : AppRoutes.habitsQuotes;
    case WidgetConstants.openHost:
      return AppRoutes.habits;
    case WidgetConstants.widgetHost:
      return AppRoutes.habits;
  }
  return null;
}
