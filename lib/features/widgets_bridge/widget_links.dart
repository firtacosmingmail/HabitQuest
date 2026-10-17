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

/// The in-app location for a widget URI that opened the app (go_router
/// sees the platform deep link with its host), or `null` if [uri] is not a
/// widget URI. A check-off URI lands on the Habits tab (the check-off itself
/// is done by the caller).
String? widgetDeepLinkLocation(Uri uri) {
  if (uri.scheme != WidgetConstants.urlScheme && uri.host.isEmpty) {
    return null;
  }
  if (!_isAppScheme(uri)) return null;
  switch (uri.host) {
    case WidgetConstants.quotesHost:
      return uri.path == '/saved' ? AppRoutes.savedQuotes : AppRoutes.quotes;
    case WidgetConstants.openHost:
      return AppRoutes.habits;
    case WidgetConstants.widgetHost:
      return AppRoutes.habits;
  }
  return null;
}
