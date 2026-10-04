import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Browser Notification API via package:web. Every call is guarded: the
/// API may be missing (older Safari, insecure origin, some WebViews) or
/// throw (e.g. Chrome on Android requires a service worker).
class BrowserNotifications {
  const BrowserNotifications();

  bool get isSupported {
    try {
      return globalContext.has('Notification');
    } catch (_) {
      return false;
    }
  }

  String get permission {
    if (!isSupported) return 'unsupported';
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'unsupported';
    }
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      if (web.Notification.permission == 'granted') return true;
      if (web.Notification.permission == 'denied') return false;
      final result = await web.Notification.requestPermission().toDart;
      return result.toDart == 'granted';
    } catch (e) {
      debugPrint('Notifications: browser permission request failed: $e');
      return false;
    }
  }

  bool show(String title, String body) {
    if (permission != 'granted') return false;
    try {
      web.Notification(title, web.NotificationOptions(body: body));
      return true;
    } catch (e) {
      debugPrint('Notifications: browser notification failed: $e');
      return false;
    }
  }
}
