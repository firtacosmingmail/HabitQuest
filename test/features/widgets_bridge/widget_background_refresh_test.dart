import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/config/backend_config.dart';
import 'package:habit_quest/core/utils/dates.dart';
import 'package:habit_quest/data/models/completion_log.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/models/quote.dart';
import 'package:habit_quest/data/remote/api_transport.dart';
import 'package:habit_quest/data/remote/session.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/widgets_bridge/widget_background_refresh.dart';
import 'package:habit_quest/features/widgets_bridge/widget_constants.dart';
import 'package:habit_quest/features/widgets_bridge/widget_links.dart';
import 'package:habit_quest/features/widgets_bridge/widget_snapshot.dart';
import 'package:habit_quest/features/widgets_bridge/widget_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fixtures.dart';

const _config = BackendConfig(
  supabaseUrl: 'https://proj.supabase.co',
  anonKey: 'anon-key',
);

/// Just after local midnight on 2026-10-23; the snapshot is from the 22nd.
final now = DateTime(2026, 10, 23, 0, 1);
const yesterday = '2026-10-22';
const todayKey = '2026-10-23';

Session sessionExpiringAt(DateTime exp, {String n = '1'}) => Session(
  accessToken: 'access-$n',
  refreshToken: 'refresh-$n',
  expiresAt: exp,
  user: const AuthUser(id: 'u1', email: 'hero@example.com'),
);

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _dailyJson(String date, String text) => {
  'date': date,
  'fallback': false,
  'quote': {
    'id': 'q-$date',
    'text': text,
    'author': 'Seneca',
    'day': date,
    'loved': false,
  },
};

/// A signed-in snapshot of [date]: `a` (done) and `b` due, plus the
/// precomputed coming days (`a` is daily, `w` only on Fridays: 2026-10-23
/// is a Friday).
String snapshotOf({
  String date = yesterday,
  String? quoteDay = yesterday,
}) {
  final a = habit(id: 'a');
  final b = habit(id: 'b');
  final w = habit(
    id: 'w',
    schedule: WeekdaysSchedule({DateTime.friday}),
  );
  final day = parseDateKey(date);
  return buildWidgetSnapshot(
    signedIn: true,
    today: day,
    dueToday: [a, b],
    log: CompletionLog.fromDates({
      'a': [day],
    }),
    quote: const Quote(id: 'q-old', text: 'Old quote', author: 'Ada'),
    quoteDay: quoteDay == null ? null : parseDateKey(quoteDay),
    allHabits: [a, w],
    now: day.add(const Duration(hours: 20)),
  ).encode();
}

void main() {
  late MemoryWidgetStore store;
  late InMemorySessionStore sessions;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) answer;

  setUp(() {
    store = MemoryWidgetStore({WidgetConstants.snapshotKey: snapshotOf()});
    sessions = InMemorySessionStore(
      sessionExpiringAt(DateTime.utc(2100)),
    );
    requests = [];
    answer = (r) async => _json(_dailyJson(todayKey, 'New quote'));
  });

  WidgetSnapshot stored() =>
      WidgetSnapshot.tryDecode(store.data[WidgetConstants.snapshotKey])!;

  Future<WidgetRefreshOutcome> run({SessionStore? sessionStore}) =>
      refreshWidgetSnapshotInBackground(
        store: store,
        sessions: sessionStore ?? sessions,
        now: now,
        overrides: [
          backendConfigProvider.overrideWithValue(_config),
          clockProvider.overrideWithValue(() => now),
          apiTransportProvider.overrideWithValue(
            ApiTransport(
              client: MockClient((r) {
                requests.add(r);
                return answer(r);
              }),
              config: _config,
            ),
          ),
        ],
      );

  group('day rollover', () {
    test('rolls the habits over from local data and fetches today\'s quote',
        () async {
      final outcome = await run();

      expect(outcome, WidgetRefreshOutcome.updated);
      final s = stored();
      expect(s.date, todayKey);
      expect(s.state, WidgetSnapshotState.ok);
      // Today's precomputed due habits (Friday: a and w), none done.
      expect(s.habits.map((h) => h.id), ['a', 'w']);
      expect(s.habits.every((h) => !h.done), isTrue);
      expect(s.upcoming.first.date, '2026-10-24');
      expect(s.upcoming.every((u) => u.date.compareTo(todayKey) > 0), isTrue);
      expect(s.quote!.text, 'New quote');
      expect(s.quote!.day, todayKey);
      expect(store.refreshCount, greaterThanOrEqualTo(1));

      final r = requests.single;
      expect(r.url.path, '/functions/v1/quotes');
      expect(r.url.queryParameters, {'date': todayKey});
      expect(r.headers['authorization'], 'Bearer access-1');
    });

    test('nothing to do when the snapshot already has today\'s quote',
        () async {
      store.data[WidgetConstants.snapshotKey] = snapshotOf(
        date: todayKey,
        quoteDay: todayKey,
      );
      final before = store.data[WidgetConstants.snapshotKey];

      expect(await run(), WidgetRefreshOutcome.upToDate);
      expect(requests, isEmpty);
      expect(store.refreshCount, 0);
      expect(store.data[WidgetConstants.snapshotKey], before);
    });

    test('a snapshot without a quote day (older app) is refreshed', () async {
      store.data[WidgetConstants.snapshotKey] = snapshotOf(
        date: todayKey,
        quoteDay: null,
      );
      expect(await run(), WidgetRefreshOutcome.updated);
      expect(stored().quote!.day, todayKey);
    });

    test('past the precomputed window, keeps the old list, not done', () {
      final s = WidgetSnapshot.tryDecode(snapshotOf())!;
      final rolled = s.rolledOverTo('2026-11-30');
      expect(rolled.date, '2026-11-30');
      expect(rolled.habits.map((h) => (h.id, h.done)), [
        ('a', false),
        ('b', false),
      ]);
      expect(rolled.upcoming, isEmpty);
      expect(identical(s.rolledOverTo(yesterday), s), isTrue);
    });
  });

  group('offline / server errors', () {
    test('offline: habits roll over, yesterday\'s quote stays, retry later',
        () async {
      answer = (_) async => throw http.ClientException('no network');

      expect(await run(), WidgetRefreshOutcome.retryLater);
      final s = stored();
      expect(s.date, todayKey);
      expect(s.habits.map((h) => h.id), ['a', 'w']);
      expect(s.quote!.text, 'Old quote');
      expect(s.quote!.day, yesterday);
      // The session is kept.
      expect(sessions.session, isNotNull);
    });

    test('a server error leaves the snapshot untouched', () async {
      store.data[WidgetConstants.snapshotKey] = snapshotOf(date: todayKey);
      final before = store.data[WidgetConstants.snapshotKey];
      answer = (_) async => _json({
        'error': {'code': 'internal_error', 'message': 'boom'},
      }, 500);

      expect(await run(), WidgetRefreshOutcome.retryLater);
      expect(store.data[WidgetConstants.snapshotKey], before);
      expect(store.refreshCount, 0);
    });

    test('an unreadable session store changes nothing (no sign-out)',
        () async {
      final before = store.data[WidgetConstants.snapshotKey];
      expect(
        await run(sessionStore: _ThrowingSessionStore()),
        WidgetRefreshOutcome.retryLater,
      );
      expect(store.data[WidgetConstants.snapshotKey], before);
      expect(requests, isEmpty);
    });

    test('no quotes on the server (404) keeps the old quote', () async {
      answer = (_) async => _json({
        'error': {'code': 'not_found', 'message': 'none'},
      }, 404);
      expect(await run(), WidgetRefreshOutcome.updated); // rolled over
      expect(stored().quote!.text, 'Old quote');
    });
  });

  group('signed out', () {
    test('no stored session: the "Open HabitQuest" state, no request',
        () async {
      sessions.session = null;

      expect(await run(), WidgetRefreshOutcome.signedOut);
      final s = stored();
      expect(s.state, WidgetSnapshotState.signedOut);
      expect(s.habits, isEmpty);
      expect(s.quote, isNull);
      expect(requests, isEmpty);

      // Running again does not rewrite or refresh.
      final count = store.refreshCount;
      expect(await run(), WidgetRefreshOutcome.signedOut);
      expect(store.refreshCount, count);
    });

    test('a signed-out snapshot is left to the app', () async {
      store.data[WidgetConstants.snapshotKey] = buildWidgetSnapshot(
        signedIn: false,
        today: parseDateKey(yesterday),
        dueToday: const [],
        log: const CompletionLog.empty(),
        now: now,
      ).encode();
      expect(await run(), WidgetRefreshOutcome.upToDate);
      expect(requests, isEmpty);
    });

    test('no snapshot at all (the app never ran): nothing written', () async {
      store.data.clear();
      expect(await run(), WidgetRefreshOutcome.upToDate);
      expect(store.data, isEmpty);
    });
  });

  group('token refresh (reuses AuthController)', () {
    test('an expired access token is refreshed, stored and used', () async {
      sessions.session = sessionExpiringAt(DateTime.utc(2026, 10, 22));
      answer = (r) async {
        if (r.url.path.endsWith('/auth-refresh')) {
          expect(jsonDecode(r.body), {'refreshToken': 'refresh-1'});
          return _json({
            'session': sessionExpiringAt(DateTime.utc(2100), n: '2').toJson(),
          });
        }
        return _json(_dailyJson(todayKey, 'New quote'));
      };

      expect(await run(), WidgetRefreshOutcome.updated);
      expect(requests.map((r) => r.url.path), [
        '/functions/v1/auth-refresh',
        '/functions/v1/quotes',
      ]);
      expect(requests.last.headers['authorization'], 'Bearer access-2');
      expect(sessions.session!.refreshToken, 'refresh-2');
      expect(stored().quote!.text, 'New quote');
    });

    test('a 401 on the quote refreshes once and retries', () async {
      var quoteCalls = 0;
      answer = (r) async {
        if (r.url.path.endsWith('/auth-refresh')) {
          return _json({
            'session': sessionExpiringAt(DateTime.utc(2100), n: '2').toJson(),
          });
        }
        if (quoteCalls++ == 0) {
          return _json({
            'error': {'code': 'unauthorized', 'message': 'expired'},
          }, 401);
        }
        return _json(_dailyJson(todayKey, 'New quote'));
      };
      expect(await run(), WidgetRefreshOutcome.updated);
      expect(requests.last.headers['authorization'], 'Bearer access-2');
    });

    test('a rejected refresh token signs out (session cleared)', () async {
      sessions.session = sessionExpiringAt(DateTime.utc(2026, 10, 22));
      answer = (r) async => _json({
        'error': {'code': 'invalid_refresh_token', 'message': 'dead'},
      }, 401);

      expect(await run(), WidgetRefreshOutcome.signedOut);
      expect(sessions.session, isNull);
      expect(stored().state, WidgetSnapshotState.signedOut);
    });

    test('a refresh that fails offline keeps the session and the quote',
        () async {
      sessions.session = sessionExpiringAt(DateTime.utc(2026, 10, 22));
      answer = (_) async => throw http.ClientException('no network');

      expect(await run(), WidgetRefreshOutcome.retryLater);
      expect(sessions.session!.refreshToken, 'refresh-1');
      expect(stored().quote!.text, 'Old quote');
      expect(stored().state, WidgetSnapshotState.ok);
    });
  });

  test('the refresh URI is recognised and is not a check-off', () {
    final uri = Uri.parse(WidgetConstants.refreshUri);
    expect(isWidgetRefreshUri(uri), isTrue);
    expect(toggleHabitId(uri), isNull);
    expect(isWidgetRefreshUri(Uri.parse(WidgetConstants.toggleUri('a'))),
        isFalse);
    expect(isWidgetRefreshUri(Uri.parse(WidgetConstants.quotesUri)), isFalse);
    expect(isWidgetRefreshUri(null), isFalse);
  });
}

class _ThrowingSessionStore implements SessionStore {
  @override
  Future<Session?> read() async => throw StateError('keystore unavailable');

  @override
  Future<void> write(Session session) async {}

  @override
  Future<void> clear() async => fail('must not clear the session');
}
