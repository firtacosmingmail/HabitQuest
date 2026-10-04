/// Browser Notification API bridge. On non-web platforms every call is a
/// harmless no-op (see the stub).
library;

export 'browser_notifications_stub.dart'
    if (dart.library.js_interop) 'browser_notifications_web.dart';
