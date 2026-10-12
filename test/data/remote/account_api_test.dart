import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/remote/account_api.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/api_transport.dart';
import 'package:habit_quest/data/remote/authenticated_transport.dart';
import 'package:habit_quest/data/remote/fake_account_api.dart';
import 'package:habit_quest/data/remote/http_account_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'http_api_test.dart' show StaticTokens, config, jsonResponse;

final profileJson = {
  'id': 'u1',
  'email': 'a@b.c',
  'displayName': 'Quest Hero',
  'createdAt': '2026-03-14T08:00:00.000Z',
  'providers': ['email'],
  'hasPassword': true,
};

http.Response errorResponse(int status, String code) => jsonResponse({
  'error': {'code': code, 'message': 'msg $code'},
}, status);

void main() {
  late List<http.Request> requests;
  late StaticTokens tokens;

  HttpAccountApi apiWith(
    Future<http.Response> Function(http.Request r) handler,
  ) {
    requests = [];
    tokens = StaticTokens('tok', next: 'tok2');
    return HttpAccountApi(
      AuthenticatedTransport(
        transport: ApiTransport(
          config: config,
          client: MockClient((r) {
            requests.add(r);
            return handler(r);
          }),
        ),
        tokens: tokens,
      ),
    );
  }

  group('HttpAccountApi', () {
    test('getProfile: GET /profile with the bearer token', () async {
      final api = apiWith((_) async => jsonResponse(profileJson));
      final p = await api.getProfile();
      final r = requests.single;
      expect(r.method, 'GET');
      expect(r.url.path, '/functions/v1/profile');
      expect(r.headers['authorization'], 'Bearer tok');
      expect(r.headers['apikey'], 'anon-key');
      expect(p.id, 'u1');
      expect(p.email, 'a@b.c');
      expect(p.displayName, 'Quest Hero');
      expect(p.createdAt, DateTime.utc(2026, 3, 14, 8));
      expect(p.providers, ['email']);
      expect(p.hasPassword, isTrue);
    });

    test('getProfile parses social accounts and null names', () async {
      final api = apiWith(
        (_) async => jsonResponse({
          ...profileJson,
          'displayName': null,
          'providers': ['google'],
          'hasPassword': false,
        }),
      );
      final p = await api.getProfile();
      expect(p.displayName, isNull);
      expect(p.providers, ['google']);
      expect(p.hasPassword, isFalse);
    });

    test('updateDisplayName: PUT /profile with the trimmed name', () async {
      final api = apiWith(
        (_) async => jsonResponse({...profileJson, 'displayName': 'New'}),
      );
      final p = await api.updateDisplayName('  New  ');
      final r = requests.single;
      expect(r.method, 'PUT');
      expect(r.url.path, '/functions/v1/profile');
      expect(jsonDecode(r.body), {'displayName': 'New'});
      expect(p.displayName, 'New');
    });

    test('changePassword: POST with both passwords, 204', () async {
      final api = apiWith((_) async => http.Response('', 204));
      await api.changePassword(currentPassword: 'old', newPassword: 'newpw1');
      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/functions/v1/auth-change-password');
      expect(jsonDecode(r.body), {
        'currentPassword': 'old',
        'newPassword': 'newpw1',
      });
    });

    test(
      'changePassword: wrong current password is not a token refresh',
      () async {
        final api = apiWith(
          (_) async => errorResponse(401, ApiException.invalidCredentials),
        );
        await expectLater(
          api.changePassword(currentPassword: 'x', newPassword: 'newpw1'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', ApiException.invalidCredentials)
                .having((e) => e.status, 'status', 401),
          ),
        );
        expect(requests, hasLength(1));
        expect(tokens.rejected, isEmpty);
      },
    );

    test('changePassword maps no_password and weak_password', () async {
      var api = apiWith((_) async => errorResponse(409, 'no_password'));
      await expectLater(
        api.changePassword(currentPassword: 'x', newPassword: 'newpw1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.noPassword,
          ),
        ),
      );
      api = apiWith((_) async => errorResponse(400, 'weak_password'));
      await expectLater(
        api.changePassword(currentPassword: 'x', newPassword: 'y'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.weakPassword,
          ),
        ),
      );
    });

    test('deleteAccount: POST {"confirm":"DELETE"}, 204', () async {
      final api = apiWith((_) async => http.Response('', 204));
      await api.deleteAccount();
      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/functions/v1/account-delete');
      expect(jsonDecode(r.body), {'confirm': 'DELETE'});
      expect(r.headers['authorization'], 'Bearer tok');
    });

    test('an expired token is refreshed once and the call retried', () async {
      var n = 0;
      final api = apiWith(
        (_) async => n++ == 0
            ? errorResponse(401, ApiException.unauthorized)
            : http.Response('', 204),
      );
      await api.deleteAccount();
      expect(requests.map((r) => r.headers['authorization']), [
        'Bearer tok',
        'Bearer tok2',
      ]);
      expect(tokens.rejected, ['tok']);
    });

    test('network failures surface as isNetwork', () async {
      final api = apiWith((_) async => throw http.ClientException('down'));
      await expectLater(
        api.deleteAccount(),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'net', true)),
      );
    });
  });

  group('FakeAccountApi', () {
    test('follows the server rules', () async {
      final fake = FakeAccountApi(password: 'secret1');
      expect((await fake.updateDisplayName(' Bob ')).displayName, 'Bob');
      expect(() => fake.updateDisplayName('   '), throwsA(isA<ApiException>()));
      expect(
        () => fake.changePassword(currentPassword: 'no', newPassword: 'newpw1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.invalidCredentials,
          ),
        ),
      );
      await fake.changePassword(
        currentPassword: 'secret1',
        newPassword: 'abcdef',
      );
      expect(fake.password, 'abcdef');
      fake.profile = AccountProfile(
        id: 'g',
        email: 'g@x.y',
        providers: const ['google'],
        hasPassword: false,
      );
      expect(
        () => fake.changePassword(currentPassword: 'a', newPassword: 'abcdefg'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.noPassword,
          ),
        ),
      );
      fake.offline = true;
      expect(
        fake.deleteAccount,
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'net', true)),
      );
      expect(fake.deleted, isFalse);
    });
  });
}
