import '../../data/remote/api_exception.dart';

/// Friendly, playful copy for auth failures.
String friendlyAuthError(Object error) {
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
