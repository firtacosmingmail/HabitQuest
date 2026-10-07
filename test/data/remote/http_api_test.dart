import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/config/backend_config.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/api_transport.dart';
import 'package:habit_quest/data/remote/authenticated_transport.dart';
import 'package:habit_quest/data/remote/http_auth_api.dart';
import 'package:habit_quest/data/remote/http_habit_quest_api.dart';
import 'package:habit_quest/data/remote/remote_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const config = BackendConfig(
  supabaseUrl: 'https://proj.supabase.co/',
  anonKey: 'anon-key',
);

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> sessionJson(String n, {int exp = 1791364500}) => {
  'accessToken': 'access-$n',
  'refreshToken': 'refresh-$n',
  'expiresAt': exp,
  'user': {'id': 'u1', 'email': 'a@b.c'},
};

final habitJson = {
  'id': 'h1',
  'name': 'Drink water',
  'emoji': '💧',
  'color': 4283215696,
  'schedule': {'type': 'daily'},
  'reminderTime': '08:30',
  'createdAt': '2026-10-01T08:00:00.000Z',
  'archived': false,
  'updatedAt': '2026-10-07T09:15:00.000Z',
  'deletedAt': null,
};

final checkInJson = {
  'id': 'h1_2026-10-07',
  'habitId': 'h1',
  'date': '2026-10-07',
  'completed': true,
  'updatedAt': '2026-10-07T09:15:00.000Z',
  'deletedAt': null,
};

/// Static token provider recording refresh calls.
class StaticTokens implements AccessTokenProvider {
  String? token;
  String? next;
  final rejected = <String>[];

  StaticTokens(this.token, {this.next});

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) async {
    rejected.add(rejectedToken);
    token = next;
    return next;
  }
}

void main() {
  group('BackendConfig', () {
    test('builds function URLs and isConfigured', () {
      expect(
        config
            .function('habits', path: ['h 1'], query: {'since': 'x'})
            .toString(),
        'https://proj.supabase.co/functions/v1/habits/h%201?since=x',
      );
      expect(config.isConfigured, isTrue);
      expect(
        const BackendConfig(supabaseUrl: 'https://x', anonKey: '').isConfigured,
        isFalse,
      );
      expect(
        BackendConfig.fromEnvironment().supabaseUrl,
        BackendConfig.defaultSupabaseUrl,
      );
    });
  });

  group('ApiTransport', () {
    test('sends apikey, bearer and JSON headers', () async {
      late http.Request seen;
      final t = ApiTransport(
        config: config,
        client: MockClient((r) async {
          seen = r;
          return jsonResponse({'ok': true});
        }),
      );
      await t.send('POST', 'habits', body: {'a': 1}, accessToken: 'tok');
      expect(seen.method, 'POST');
      expect(
        seen.url.toString(),
        'https://proj.supabase.co/functions/v1/habits',
      );
      expect(seen.headers['apikey'], 'anon-key');
      expect(seen.headers['authorization'], 'Bearer tok');
      expect(seen.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), {'a': 1});
    });

    test('no Authorization header without a token', () async {
      late http.Request seen;
      final t = ApiTransport(
        config: config,
        client: MockClient((r) async {
          seen = r;
          return jsonResponse({});
        }),
      );
      await t.send('POST', 'auth-login', body: {});
      expect(seen.headers.containsKey('authorization'), isFalse);
      expect(seen.headers['apikey'], 'anon-key');
    });

    test('maps the error body to ApiException', () async {
      final t = ApiTransport(
        config: config,
        client: MockClient(
          (_) async => jsonResponse({
            'error': {'code': 'email_taken', 'message': 'taken'},
          }, 409),
        ),
      );
      await expectLater(
        t.send('POST', 'auth-register'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.code, 'code', 'email_taken')
              .having((e) => e.message, 'message', 'taken'),
        ),
      );
    });

    test('non-JSON errors fall back to a code from the status', () async {
      final t = ApiTransport(
        config: config,
        client: MockClient((_) async => http.Response('<html>oops', 502)),
      );
      await expectLater(
        t.send('GET', 'habits'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 502)
              .having((e) => e.code, 'code', ApiException.internalError),
        ),
      );
    });

    test('401 without body is unauthorized', () async {
      final t = ApiTransport(
        config: config,
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(
        t.send('GET', 'habits'),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'u', true)),
      );
    });

    test('client exceptions become network errors', () async {
      final t = ApiTransport(
        config: config,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        t.send('GET', 'habits'),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'net', true)),
      );
    });

    test('refuses to send when the anon key is missing', () async {
      var called = false;
      final t = ApiTransport(
        config: const BackendConfig(supabaseUrl: 'https://x', anonKey: ''),
        client: MockClient((_) async {
          called = true;
          return jsonResponse({});
        }),
      );
      await expectLater(
        t.send('GET', 'habits'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.notConfigured,
          ),
        ),
      );
      expect(called, isFalse);
    });

    test('204 returns null', () async {
      final t = ApiTransport(
        config: config,
        client: MockClient((_) async => http.Response('', 204)),
      );
      expect(await t.send('POST', 'auth-logout', accessToken: 'x'), isNull);
    });
  });

  group('HttpAuthApi', () {
    test('register → session, and needsConfirmation', () async {
      final requests = <http.Request>[];
      var confirm = false;
      final api = HttpAuthApi(
        ApiTransport(
          config: config,
          client: MockClient((r) async {
            requests.add(r);
            return confirm
                ? jsonResponse({'session': null, 'needsConfirmation': true})
                : jsonResponse({'session': sessionJson('1')});
          }),
        ),
      );
      final r1 = await api.register(
        email: 'a@b.c',
        password: 'secret1',
        displayName: ' Ann ',
      );
      expect(r1.session!.accessToken, 'access-1');
      expect(
        r1.session!.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1791364500000, isUtc: true),
      );
      expect(requests.single.url.path, '/functions/v1/auth-register');
      expect(jsonDecode(requests.single.body), {
        'email': 'a@b.c',
        'password': 'secret1',
        'displayName': 'Ann',
      });

      confirm = true;
      final r2 = await api.register(email: 'a@b.c', password: 'secret1');
      expect(r2.needsConfirmation, isTrue);
      expect(r2.session, isNull);
      expect(jsonDecode(requests.last.body).containsKey('displayName'), false);
    });

    test('login, refresh and logout hit the right functions', () async {
      final requests = <http.Request>[];
      final api = HttpAuthApi(
        ApiTransport(
          config: config,
          client: MockClient((r) async {
            requests.add(r);
            if (r.url.path.endsWith('auth-logout')) {
              return http.Response('', 204);
            }
            return jsonResponse({'session': sessionJson('2')});
          }),
        ),
      );
      await api.login(email: 'a@b.c', password: 'pw');
      await api.refresh('refresh-1');
      await api.logout('access-2');
      expect(requests.map((r) => r.url.pathSegments.last), [
        'auth-login',
        'auth-refresh',
        'auth-logout',
      ]);
      expect(jsonDecode(requests[1].body), {'refreshToken': 'refresh-1'});
      expect(requests[2].headers['authorization'], 'Bearer access-2');
      expect(requests[2].method, 'POST');
    });

    test('invalid credentials surface as ApiException', () async {
      final api = HttpAuthApi(
        ApiTransport(
          config: config,
          client: MockClient(
            (_) async => jsonResponse({
              'error': {'code': 'invalid_credentials', 'message': 'nope'},
            }, 401),
          ),
        ),
      );
      await expectLater(
        api.login(email: 'a@b.c', password: 'x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.invalidCredentials,
          ),
        ),
      );
    });
  });

  group('HttpHabitQuestApi', () {
    late List<http.Request> requests;
    late http.Response Function(http.Request) handler;
    late StaticTokens tokens;
    late HttpHabitQuestApi api;

    setUp(() {
      requests = [];
      tokens = StaticTokens('tok-1', next: 'tok-2');
      handler = (_) => jsonResponse({});
      api = HttpHabitQuestApi(
        AuthenticatedTransport(
          transport: ApiTransport(
            config: config,
            client: MockClient((r) async {
              requests.add(r);
              return handler(r);
            }),
          ),
          tokens: tokens,
        ),
      );
    });

    test('listHabits sends since and parses items + serverTime', () async {
      handler = (_) => jsonResponse({
        'items': [habitJson],
        'serverTime': '2026-10-07T10:00:00.000Z',
      });
      final page = await api.listHabits(
        since: DateTime.utc(2026, 10, 7, 9, 0, 0, 123, 456),
      );
      final r = requests.single;
      expect(r.method, 'GET');
      expect(r.url.path, '/functions/v1/habits');
      expect(r.url.queryParameters['since'], '2026-10-07T09:00:00.123Z');
      expect(r.headers['authorization'], 'Bearer tok-1');
      expect(r.headers['apikey'], 'anon-key');
      expect(page.serverTime, DateTime.utc(2026, 10, 7, 10));
      final h = page.items.single;
      expect(h.id, 'h1');
      expect(h.schedule, {'type': 'daily'});
      expect(h.reminderTime, '08:30');
      expect(h.toJson(), habitJson);
    });

    test('putHabit PUTs to /habits/<id> and parses applied', () async {
      handler = (_) => jsonResponse({'item': habitJson, 'applied': false});
      final habit = RemoteHabit.fromJson(habitJson);
      final res = await api.putHabit(habit);
      expect(requests.single.method, 'PUT');
      expect(requests.single.url.path, '/functions/v1/habits/h1');
      expect(jsonDecode(requests.single.body), habitJson);
      expect(res.applied, isFalse);
      expect(res.item, habit);
    });

    test('deleteHabit sends updatedAt as a query parameter', () async {
      handler = (_) => jsonResponse({
        'item': {...habitJson, 'deletedAt': '2026-10-08T00:00:00.000Z'},
        'applied': true,
      });
      final res = await api.deleteHabit(
        'h1',
        updatedAt: DateTime.utc(2026, 10, 8),
      );
      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.path, '/functions/v1/habits/h1');
      expect(
        requests.single.url.queryParameters['updatedAt'],
        '2026-10-08T00:00:00.000Z',
      );
      expect(res.item.isDeleted, isTrue);
    });

    test('getHabit returns null on 404 not_found', () async {
      handler = (_) => jsonResponse({
        'error': {'code': 'not_found', 'message': 'x'},
      }, 404);
      expect(await api.getHabit('nope'), isNull);
    });

    test('batchHabits posts items to /habits/batch', () async {
      handler = (_) => jsonResponse({
        'results': [
          {'id': 'h1', 'applied': true, 'item': habitJson},
        ],
      });
      final res = await api.batchHabits([RemoteHabit.fromJson(habitJson)]);
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/functions/v1/habits/batch');
      expect(jsonDecode(requests.single.body), {
        'items': [habitJson],
      });
      expect(res.single.applied, isTrue);
      expect(await api.batchHabits([]), isEmpty);
      expect(requests, hasLength(1));
    });

    test('check-ins: list with habitId, put, batch', () async {
      handler = (r) => r.method == 'GET'
          ? jsonResponse({
              'items': [checkInJson],
              'serverTime': '2026-10-07T10:00:00.000Z',
            })
          : r.url.path.endsWith('batch')
          ? jsonResponse({
              'results': [
                {'id': 'h1_2026-10-07', 'applied': true, 'item': checkInJson},
              ],
            })
          : jsonResponse({'item': checkInJson, 'applied': true});
      final page = await api.listCheckIns(habitId: 'h1');
      expect(requests.last.url.queryParameters, {'habitId': 'h1'});
      final c = page.items.single;
      expect(c.id, 'h1_2026-10-07');
      expect(c.date, DateTime(2026, 10, 7));
      expect(c.toJson(), checkInJson);

      await api.putCheckIn(c);
      expect(requests.last.url.path, '/functions/v1/check-ins/h1_2026-10-07');
      final b = await api.batchCheckIns([c]);
      expect(requests.last.url.path, '/functions/v1/check-ins/batch');
      expect(b.single.id, 'h1_2026-10-07');
    });

    test('game-state get / put / delete', () async {
      final gs = {
        'state': {'xp': 120},
        'updatedAt': '2026-10-07T09:15:00.000Z',
      };
      handler = (r) => switch (r.method) {
        'GET' => jsonResponse({
          'item': null,
          'serverTime': '2026-10-07T10:00:00.000Z',
        }),
        'PUT' => jsonResponse({'item': gs, 'applied': true}),
        _ => http.Response('', 204),
      };
      final snap = await api.getGameState();
      expect(snap.item, isNull);
      final put = await api.putGameState(RemoteGameState.fromJson(gs));
      expect(put.applied, isTrue);
      expect(put.item.state, {'xp': 120});
      expect(jsonDecode(requests.last.body), gs);
      await api.deleteGameState();
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'GET /functions/v1/game-state',
        'PUT /functions/v1/game-state',
        'DELETE /functions/v1/game-state',
      ]);
    });

    test('401 → refresh once → retry once with the new token', () async {
      handler = (r) => r.headers['authorization'] == 'Bearer tok-1'
          ? jsonResponse({
              'error': {'code': 'unauthorized', 'message': 'expired'},
            }, 401)
          : jsonResponse({
              'items': [],
              'serverTime': '2026-10-07T10:00:00.000Z',
            });
      final page = await api.listHabits();
      expect(page.items, isEmpty);
      expect(tokens.rejected, ['tok-1']);
      expect(requests.map((r) => r.headers['authorization']), [
        'Bearer tok-1',
        'Bearer tok-2',
      ]);
    });

    test('a second 401 after the retry is not retried again', () async {
      handler = (_) => jsonResponse({
        'error': {'code': 'unauthorized', 'message': 'expired'},
      }, 401);
      await expectLater(
        api.listHabits(),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'u', true)),
      );
      expect(requests, hasLength(2));
      expect(tokens.rejected, hasLength(1));
    });

    test('failed refresh → no retry, 401 surfaces', () async {
      tokens.next = null; // refresh failed / signed out
      handler = (_) => jsonResponse({
        'error': {'code': 'unauthorized', 'message': 'expired'},
      }, 401);
      await expectLater(api.listHabits(), throwsA(isA<ApiException>()));
      expect(requests, hasLength(1));
    });

    test('signed out → unauthorized without a request', () async {
      tokens.token = null;
      await expectLater(
        api.listHabits(),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'u', true)),
      );
      expect(requests, isEmpty);
    });

    test('other 4xx errors are not retried', () async {
      handler = (_) => jsonResponse({
        'error': {'code': 'habit_not_found', 'message': 'x'},
      }, 409);
      await expectLater(
        api.putCheckIn(RemoteCheckIn.fromJson(checkInJson)),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.habitNotFound,
          ),
        ),
      );
      expect(requests, hasLength(1));
      expect(tokens.rejected, isEmpty);
    });
  });
}
