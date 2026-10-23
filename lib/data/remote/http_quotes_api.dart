import '../../core/utils/dates.dart';
import 'authenticated_transport.dart';
import 'json_utils.dart';
import 'quotes_api.dart';

/// [QuotesApi] over HTTP (Edge Functions `quotes` and `quote-loves`).
///
/// The `GET /quotes` reads also work signed out (no `Authorization`
/// header, `loved: false`); `quote-loves` always needs a session.
class HttpQuotesApi implements QuotesApi {
  final AuthenticatedTransport transport;

  HttpQuotesApi(this.transport);

  @override
  Future<DailyQuote> quoteOfDay(DateTime date) async => DailyQuote.fromJson(
    await transport.sendForObject(
      'GET',
      'quotes',
      query: {'date': dateKey(date)},
      allowAnonymous: true,
    ),
  );

  @override
  Future<QuoteHistory> pastQuotes(int days) async => QuoteHistory.fromJson(
    await transport.sendForObject(
      'GET',
      'quotes',
      query: {'past': '$days'},
      allowAnonymous: true,
    ),
  );

  @override
  Future<QuoteHistory> quotesBetween(DateTime from, DateTime to) async =>
      QuoteHistory.fromJson(
        await transport.sendForObject(
          'GET',
          'quotes',
          query: {'from': dateKey(from), 'to': dateKey(to)},
          allowAnonymous: true,
        ),
      );

  @override
  Future<List<Quote>> lovedQuotes() async {
    final json = await transport.sendForObject('GET', 'quote-loves');
    return [for (final q in readObjectList(json, 'items')) Quote.fromJson(q)];
  }

  @override
  Future<Quote> love(String quoteId) async => Quote.fromJson(
    await transport.sendForObject(
      'POST',
      'quote-loves',
      body: {'quoteId': quoteId},
    ),
  );

  @override
  Future<void> unlove(String quoteId) async {
    await transport.send('DELETE', 'quote-loves', query: {'quoteId': quoteId});
  }
}
