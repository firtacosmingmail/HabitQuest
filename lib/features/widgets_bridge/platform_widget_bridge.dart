/// Platform hooks of the widget bridge. On web (no `dart:io`) everything is
/// a no-op and home_widget is never imported.
library;

export 'platform_widget_bridge_stub.dart'
    if (dart.library.io) 'platform_widget_bridge_io.dart';
