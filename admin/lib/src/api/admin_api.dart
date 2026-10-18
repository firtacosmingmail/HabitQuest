import 'models.dart';

/// Everything the console needs from the backend. [HttpAdminApi] talks to
/// the Edge Functions; [FakeAdminApi] is the in-memory version used by the
/// widget tests and by `--dart-define=ADMIN_DEMO=true`.
///
/// Every method except [signIn] needs a signed-in session and throws
/// [ApiException] (403 `forbidden` for non-admins, checked on the server).
abstract class AdminApi {
  /// `auth-login`. Throws 401 `invalid_credentials` etc.
  Future<AdminSession> signIn(String email, String password);

  /// `GET /admin-stats/me`: completes when the session is an admin, throws
  /// 403 `forbidden` otherwise.
  Future<void> checkAdmin();

  /// `auth-logout` (best effort) and forget the session.
  Future<void> signOut();

  /// `GET /admin-quotes`.
  Future<QuotePage> listQuotes(QuoteQuery query);

  /// `POST /quotes`. Throws 409 `day_taken`.
  Future<AdminQuote> createQuote(QuoteDraft draft);

  /// `PUT /quotes?id=` with the whole draft (text, author, day; day null =
  /// unschedule). Throws 409 `day_taken`.
  Future<AdminQuote> updateQuote(String id, QuoteDraft draft);

  /// `DELETE /admin-quotes?id=`.
  Future<void> deleteQuote(String id);

  /// `GET /admin-stats?from=&to=` (inclusive `yyyy-MM-dd`).
  Future<AdminStats> stats({required String from, required String to});
}
