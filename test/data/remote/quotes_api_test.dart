import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/config/backend_config.dart';
import 'package:habit_quest/core/utils/dates.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/api_transport.dart';
import 'package:habit_quest/data/remote/authenticated_transport.dart';
import 'package:habit_quest/data/remote/fake_quotes_api.dart';
import 'package:habit_quest/data/remote/http_quotes_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = BackendConfig(
  supabaseUrl: 'https://proj.supabase.co/',
  anonKey: 'anon-key',
);

class _Tokens implements AccessTokenProvider {
  @override
  Future<String?> accessToken() async => 'access-1';

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) async => null;
}

final _quoteJson = {
  'id': '6f1c1c1e-1b7a-4f0e-9a43-3d2b9c0f5e11',
  'text': 'Well done is better than well said.',
  'author': 'Benjamin Franklin',
  'day': '2026-11-14',
  'createdAt': '2026-10-16T12:00:00.000Z',
  'updatedAt': '2026-10-16T12:00:00.000Z',
  'loved': false,
};

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('HttpQuotesApi', () {
    late List<http.Request> requests;
    late http.Response Function(http.Request) answer;
    late HttpQuotesApi api;

    setUp(() {
      requests = [];
      answer = (_) => _json({});
      api = HttpQuotesApi(
        AuthenticatedTransport(
          transport: ApiTransport(
            client: MockClient((r) async {
              requests.add(r);
              return answer(r);
            }),
            config: _config,
          ),
          tokens: _Tokens(),
        ),
      );
    });

    test(
      'quoteOfDay sends ?date= with the given local day and parses',
      () async {
        answer = (_) => _json({
          'date': '2026-11-14',
          'fallback': false,
          'quote': _quoteJson,
        });
        final daily = await api.quoteOfDay(DateTime(2026, 11, 14, 23, 30));

        final r = requests.single;
        expect(r.method, 'GET');
        expect(r.url.path, '/functions/v1/quotes');
        expect(r.url.queryParameters, {'date': '2026-11-14'});
        expect(r.headers['authorization'], 'Bearer access-1');
        expect(r.headers['apikey'], 'anon-key');
        expect(daily.date, DateTime(2026, 11, 14));
        expect(daily.fallback, isFalse);
        expect(daily.quote.text, 'Well done is better than well said.');
        expect(daily.quote.author, 'Benjamin Franklin');
        expect(daily.quote.day, DateTime(2026, 11, 14));
        expect(daily.quote.loved, isFalse);
      },
    );

    test('quoteOfDay maps 404 to not_found', () async {
      answer = (_) => _json({
        'error': {'code': 'not_found', 'message': 'No quotes'},
      }, 404);
      await expectLater(
        api.quoteOfDay(DateTime(2026, 11, 14)),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 404)
              .having((e) => e.code, 'code', ApiException.notFound),
        ),
      );
    });

    test(
      'history: ?past=N and ?from=&to=, newest first, null author',
      () async {
        answer = (_) => _json({
          'from': '2026-10-17',
          'to': '2026-10-19',
          'items': [
            {..._quoteJson, 'id': 'b', 'day': '2026-10-19', 'author': null},
            {..._quoteJson, 'id': 'a', 'day': '2026-10-17', 'loved': true},
          ],
        });
        final past = await api.pastQuotes(3);
        final range = await api.quotesBetween(
          DateTime(2026, 10, 17),
          DateTime(2026, 10, 19),
        );

        expect(requests[0].url.queryParameters, {'past': '3'});
        expect(requests[1].url.queryParameters, {
          'from': '2026-10-17',
          'to': '2026-10-19',
        });
        for (final h in [past, range]) {
          expect(h.from, DateTime(2026, 10, 17));
          expect(h.to, DateTime(2026, 10, 19));
          expect(h.items.map((q) => q.id), ['b', 'a']);
          expect(h.items.first.author, isNull);
          expect(h.items.first.attribution, '— Unknown');
          expect(h.items.last.loved, isTrue);
        }
      },
    );

    test('quote-loves: GET items, POST {quoteId}, DELETE ?quoteId=', () async {
      final item = {
        ..._quoteJson,
        'loved': true,
        'lovedAt': '2026-10-20T07:30:00.000Z',
      };
      answer = (r) => switch (r.method) {
        'GET' => _json({
          'items': [item],
        }),
        'POST' => _json(item),
        _ => http.Response('', 204),
      };

      final loved = await api.lovedQuotes();
      final one = await api.love(_quoteJson['id'] as String);
      await api.unlove(_quoteJson['id'] as String);

      expect(loved.single.loved, isTrue);
      expect(loved.single.lovedAt, DateTime.utc(2026, 10, 20, 7, 30));
      expect(one.lovedAt, DateTime.utc(2026, 10, 20, 7, 30));
      expect([for (final r in requests) r.method], ['GET', 'POST', 'DELETE']);
      for (final r in requests) {
        expect(r.url.path, '/functions/v1/quote-loves');
        expect(r.headers['authorization'], 'Bearer access-1');
      }
      expect(jsonDecode(requests[1].body), {'quoteId': _quoteJson['id']});
      expect(requests[2].url.queryParameters, {'quoteId': _quoteJson['id']});
    });

    test('Quote JSON round-trips', () async {
      final item = {
        ..._quoteJson,
        'loved': true,
        'lovedAt': '2026-10-20T07:30:00.000Z',
      };
      answer = (_) => _json(item);
      final q = await api.love('x');
      expect(q.toJson(), item);
    });
  });

  group('FakeQuotesApi', () {
    // Noon, so the server's UTC day is the same calendar day.
    DateTime clock() => DateTime(2026, 10, 18, 12);

    test('returns the scheduled quote of the day', () async {
      final api = FakeQuotesApi(now: clock);
      final daily = await api.quoteOfDay(DateTime(2026, 10, 18));
      expect(daily.fallback, isFalse);
      expect(daily.quote.id, 'q3');
    });

    test('falls back deterministically among older quotes', () async {
      final api = FakeQuotesApi(now: clock);
      final date = DateTime(2026, 10, 25);
      final a = await api.quoteOfDay(date);
      final b = await api.quoteOfDay(date);
      final index = daysBetween(DateTime(1970), date) % 5;
      expect(a.fallback, isTrue);
      expect(a.quote.id, 'q${index + 1}');
      expect(b.quote.id, a.quote.id);
      // Before every scheduled day: all quotes are the pool.
      final early = await api.quoteOfDay(DateTime(2026, 1, 1));
      expect(early.fallback, isTrue);
      expect(
        early.quote.id,
        'q${daysBetween(DateTime(1970), DateTime(2026)) % 5 + 1}',
      );
    });

    test('404 without quotes', () async {
      final api = FakeQuotesApi(quotes: const []);
      await expectLater(
        api.quoteOfDay(DateTime(2026, 10, 18)),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
    });

    test('history never includes today or future days', () async {
      final api = FakeQuotesApi(now: clock);
      final past = await api.pastQuotes(30);
      expect(past.items.map((q) => q.id), ['q2', 'q1']);
      final range = await api.quotesBetween(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 30),
      );
      expect(range.items.map((q) => q.id), ['q3', 'q2', 'q1']);
    });

    test('love / unlove are idempotent; loves list newest first', () async {
      var now = DateTime.utc(2026, 10, 18, 8);
      final api = FakeQuotesApi(now: () => now);
      final first = await api.love('q1');
      now = now.add(const Duration(hours: 1));
      await api.love('q2');
      final again = await api.love('q1');
      expect(again.lovedAt, first.lovedAt);
      expect((await api.lovedQuotes()).map((q) => q.id), ['q2', 'q1']);
      expect(
        (await api.quoteOfDay(DateTime(2026, 10, 16))).quote.loved,
        isTrue,
      );

      await api.unlove('q1');
      await api.unlove('q1');
      await api.unlove('missing');
      expect((await api.lovedQuotes()).map((q) => q.id), ['q2']);
      await expectLater(
        api.love('missing'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
    });
  });
}
