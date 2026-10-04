/// Non-web stand-in for the browser Notification API.
class BrowserNotifications {
  const BrowserNotifications();

  /// Whether the Notification API exists in this environment.
  bool get isSupported => false;

  /// `'granted'`, `'denied'`, `'default'` or `'unsupported'`.
  String get permission => 'unsupported';

  /// Asks for permission; returns whether it is granted.
  Future<bool> requestPermission() async => false;

  /// Shows a system notification if permitted; returns whether it did.
  bool show(String title, String body) => false;
}
