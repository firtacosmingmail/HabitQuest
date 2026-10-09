import '../../features/auth/auth_callback.dart';
import '../../features/auth/auth_controller.dart';
import 'app_routes.dart';

/// The go_router auth gate:
/// - while the session loads, everything goes to the splash;
/// - signed out, everything goes to `/login`;
/// - signed in, `/login` and the splash go to `/habits` (or to the page the
///   user originally asked for, kept in a `from` query parameter).
///
/// `/auth-callback` (the email confirmation deep link) passes the gate:
/// signed out it lands on `/login?status=...&reason=...` (the login screen
/// shows the outcome); signed in it stays allowed (the router shows a
/// snackbar and keeps the user in the app).
///
/// Returns the location to redirect to, or `null` to stay.
String? authRedirect(AuthState auth, Uri uri) {
  final path = uri.path;
  final onLogin = path == AppRoutes.login;
  final onSplash = path == AppRoutes.splash;
  final onGate = onLogin || onSplash;

  // Where the user wanted to go (kept across splash → login → app).
  final wanted = onGate ? uri.queryParameters['from'] : uri.toString();

  return switch (auth) {
    AuthUnknown() => onSplash ? null : _withFrom(AppRoutes.splash, wanted),
    SignedOut() => _signedOut(onLogin, wanted),
    SignedIn() => onGate ? safeReturnLocation(wanted) : null,
  };
}

String? _signedOut(bool onLogin, String? wanted) {
  final target = wanted == null ? null : Uri.tryParse(wanted);
  if (target != null && target.path == AppRoutes.authCallback) {
    return loginWithCallback(target);
  }
  return onLogin ? null : _withFrom(AppRoutes.login, wanted);
}

/// [from] if it is an in-app location outside the auth gate, else `/habits`.
String safeReturnLocation(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return AppRoutes.habits;
  }
  final path = Uri.tryParse(from)?.path ?? '';
  if (path.isEmpty ||
      path == '/' ||
      path == AppRoutes.login ||
      path == AppRoutes.splash) {
    return AppRoutes.habits;
  }
  return from;
}

String _withFrom(String gate, String? from) {
  final target = safeReturnLocation(from);
  if (target == AppRoutes.habits) return gate;
  return Uri(path: gate, queryParameters: {'from': target}).toString();
}
