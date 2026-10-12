import '../../data/remote/api_exception.dart';
import 'oauth/oauth_sign_in.dart';

/// Friendly, playful copy for auth failures.
String friendlyAuthError(Object error, {OAuthProvider? provider}) {
  if (error is OAuthNotConfigured) {
    return "${error.provider.label} sign-in isn't set up yet.";
  }
  if (error is OAuthFailure) {
    return "Couldn't sign in with ${error.provider.label}. Please try again.";
  }
  final via = provider?.label;
  if (error is ApiException && via != null) {
    switch (error.code) {
      case ApiException.invalidToken:
        return "$via couldn't confirm it's you. Please try again.";
      case ApiException.providerDisabled:
        return "$via sign-in isn't set up yet (it's turned off on the "
            'quest server).';
      case ApiException.signupDisabled:
        return 'New sign-ups are closed right now.';
    }
  }
  if (error is! ApiException) {
    return 'Something unexpected happened. Please try again.';
  }
  return switch (error.code) {
    ApiException.invalidCredentials =>
      "That email and password don't match. Try again?",
    ApiException.emailTaken =>
      'That email already belongs to a hero. Log in instead?',
    ApiException.weakPassword =>
      'That password is too easy to guess. Try a longer one.',
    ApiException.invalidInput =>
      'Hmm, that does not look right. Check your email and password.',
    ApiException.emailNotConfirmed =>
      'Almost there! Confirm your email first (check your inbox).',
    ApiException.rateLimited =>
      'Whoa, that was a lot of tries! Take a breather and try again soon.',
    ApiException.networkError =>
      "Can't reach the quest server. Check your connection and try again.",
    ApiException.notConfigured => notConfiguredMessage,
    _ => 'The quest server stumbled. Please try again in a moment.',
  };
}

const notConfiguredMessage =
    'This build has no server key yet. Run it with '
    '--dart-define=SUPABASE_ANON_KEY=<your anon key> '
    '(see "Environment config" in the README).';
