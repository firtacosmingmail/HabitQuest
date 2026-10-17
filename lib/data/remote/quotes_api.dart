import '../models/quote.dart';

export '../models/quote.dart';

/// The `quotes` and `quote-loves` Edge Functions for the signed-in user
/// (contract: "Quotes" in `supabase/API.md`). Every method throws
/// [ApiException] on failure (`isNetwork` when offline).
abstract interface class QuotesApi {
  /// `GET /quotes?date=yyyy-MM-dd`. Pass the user's *local* calendar day.
  /// Throws `not_found` (404) when there are no quotes at all.
  Future<DailyQuote> quoteOfDay(DateTime date);

  /// `GET /quotes?past=N` (1–366): the scheduled quotes of the [days] days
  /// before the server's (UTC) today, newest day first.
  Future<QuoteHistory> pastQuotes(int days);

  /// `GET /quotes?from=&to=` (inclusive, at most 366 days; never future
  /// days): the scheduled quotes of the range, newest day first.
  Future<QuoteHistory> quotesBetween(DateTime from, DateTime to);

  /// `GET /quote-loves`: the loved quotes, newest love first (each with
  /// `loved: true` and `lovedAt`).
  Future<List<Quote>> lovedQuotes();

  /// `POST /quote-loves {quoteId}` (idempotent). Returns the loved quote
  /// with its `lovedAt`. Throws `not_found` (404) for an unknown quote.
  Future<Quote> love(String quoteId);

  /// `DELETE /quote-loves?quoteId=` (idempotent, always 204).
  Future<void> unlove(String quoteId);
}
