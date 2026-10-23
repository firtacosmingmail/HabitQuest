/// Background refresh of the widget snapshot after midnight, while the app
/// is not running (Android: `WidgetRefreshWorker` → home_widget background
/// callback with `habitquest://widget/refresh`; see `docs/WIDGETS.md`,
/// "Daily roll-over without the app").
///
/// Before this, only the running app fetched the quote of the day
/// (`GET /quotes` needs the user's bearer token), so the widgets kept
/// re-rendering yesterday's quote until the app was opened.
///
/// It reuses the app's own stack: [AuthController] (stored session, token
/// refresh, sign-out on a rejected refresh token) behind
/// [AuthenticatedTransport] and `HttpQuotesApi`, all through the same
/// Riverpod providers, in a short-lived [ProviderContainer]. It never opens
/// the hive boxes (not multi-isolate safe): the habits roll over from the
/// days the app precomputed into the snapshot (`upcoming`).
///
/// Signed out (no stored session, or the refresh token was rejected), the
/// quote is fetched **anonymously** (`GET /quotes` without an
/// `Authorization` header, "Signed-out reads" in `supabase/API.md`) through
/// the same `HttpQuotesApi` and `ApiTransport`, and written into the
/// `signedOut` snapshot: the Daily quote widget keeps showing the quote of
/// the day, Today's habits shows "Open HabitQuest". When that read fails
/// (offline, or a backend that still answers 401), the last quote stays.
library;

import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../core/utils/dates.dart';
import '../../data/models/completion_log.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/authenticated_transport.dart';
import '../../data/remote/http_quotes_api.dart';
import '../../data/remote/session.dart';
import '../auth/auth_providers.dart';
import '../auth/session_store.dart';
import 'widget_constants.dart';
import 'widget_snapshot.dart';
import 'widget_store.dart';

/// What a background refresh did.
enum WidgetRefreshOutcome {
  /// Nothing to change (the snapshot is already today's, or there is none).
  upToDate,

  /// The snapshot was rewritten (day roll-over and/or today's quote).
  updated,

  /// The user is signed out (no stored session, or the refresh token was
  /// rejected): the snapshot is in the `signedOut` state (habits: "Open
  /// HabitQuest") with the anonymously fetched quote of the day, or the
  /// last one when the server refused the anonymous read (401) or has no
  /// quotes. Offline returns [retryLater] instead.
  signedOut,

  /// The quote could not be fetched (offline, server error, unreadable
  /// session storage). The habits may have rolled over; try again later.
  retryLater,
}

/// Rolls the stored snapshot over to the local day of [now] and puts that
/// day's quote in it, then refreshes the widgets when anything changed.
///
/// * Habits: [WidgetSnapshot.rolledOverTo] (local data only, no network).
/// * Quote: fetched only when the stored one is not today's, through
///   `quotesApiProvider` with the stored session from [sessions]; an
///   expired access token is refreshed first and the new session stored.
/// * Signed out (no session, or the refresh token is rejected): the
///   `signedOut` state is written with today's quote, fetched without a
///   token when the stored one is not today's (old quote kept on failure).
/// * Any failure leaves the stored snapshot as it is (yesterday's quote
///   stays) and returns [WidgetRefreshOutcome.retryLater]. Never throws.
///
/// [overrides] are extra provider overrides (tests: the HTTP transport and
/// backend config).
Future<WidgetRefreshOutcome> refreshWidgetSnapshotInBackground({
  required WidgetStore store,
  required SessionStore sessions,
  required DateTime now,
  List<Override> overrides = const [],
}) async {
  try {
    return await _refresh(store, sessions, now, overrides);
  } on Object catch (e) {
    developer.log('Background widget refresh failed: $e', name: 'WidgetBridge');
    return WidgetRefreshOutcome.retryLater;
  }
}

Future<WidgetRefreshOutcome> _refresh(
  WidgetStore store,
  SessionStore sessions,
  DateTime now,
  List<Override> overrides,
) async {
  final todayKey = dateKey(now);
  final Session? session;
  try {
    session = await sessions.read();
  } on Object catch (e) {
    // Keystore hiccup: do not take it for a sign-out.
    developer.log('Session unreadable in background: $e', name: 'WidgetBridge');
    return WidgetRefreshOutcome.retryLater;
  }
  if (session == null) return _refreshSignedOut(store, now, overrides);

  // 1. Local roll-over first, so the habits are right even offline.
  final stored = await _readSnapshot(store);
  // No snapshot yet (the app never ran) or the app has not caught up with
  // a sign-in: leave it to the app.
  if (stored == null || stored.state == WidgetSnapshotState.signedOut) {
    return WidgetRefreshOutcome.upToDate;
  }
  var current = stored.rolledOverTo(todayKey);
  final rolled = !identical(current, stored);
  if (rolled) {
    current = current.copyWith(generatedAt: now.toUtc());
    await _write(store, current);
  }
  if (current.quote?.day == todayKey) {
    return rolled
        ? WidgetRefreshOutcome.updated
        : WidgetRefreshOutcome.upToDate;
  }

  // 2. Today's quote, through the app's auth + quotes stack.
  final container = ProviderContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(sessions),
      authControllerProvider.overrideWith(
        () =>
            AuthController(preloadedSession: session, proactiveRefresh: false),
      ),
      ...overrides,
    ],
  );
  try {
    final daily = await container
        .read(quotesApiProvider)
        .quoteOfDay(parseDateKey(todayKey));
    // Re-read: a widget check-off may have been recorded meanwhile.
    final latest = (await _readSnapshot(store) ?? current).rolledOverTo(
      todayKey,
    );
    if (latest.state == WidgetSnapshotState.signedOut) {
      return WidgetRefreshOutcome.upToDate;
    }
    await _write(
      store,
      latest.copyWith(
        quote: WidgetQuote.fromQuote(daily.quote, day: daily.date),
        generatedAt: now.toUtc(),
      ),
    );
    return WidgetRefreshOutcome.updated;
  } on ApiException catch (e) {
    if (container.read(authControllerProvider) is SignedOut) {
      // The refresh token was rejected; AuthController cleared the stored
      // session exactly as the app would.
      return _refreshSignedOut(store, now, overrides);
    }
    if (e.status == 404) {
      // No quotes on the server at all: keep what is shown.
      return rolled
          ? WidgetRefreshOutcome.updated
          : WidgetRefreshOutcome.upToDate;
    }
    developer.log('Background quote fetch failed: $e', name: 'WidgetBridge');
    return WidgetRefreshOutcome.retryLater;
  } finally {
    container.dispose();
  }
}

Future<WidgetSnapshot?> _readSnapshot(WidgetStore store) async =>
    WidgetSnapshot.tryDecode(await store.read(WidgetConstants.snapshotKey));

Future<void> _write(WidgetStore store, WidgetSnapshot snapshot) async {
  await store.write(WidgetConstants.snapshotKey, snapshot.encode());
  await store.refreshWidgets();
}

/// Signed out: the same `signedOut` snapshot the app writes, with today's
/// quote. The stored quote is kept when it is today's, or when the
/// anonymous read fails (it is better than none).
Future<WidgetRefreshOutcome> _refreshSignedOut(
  WidgetStore store,
  DateTime now,
  List<Override> overrides,
) async {
  final todayKey = dateKey(now);
  final stored = await _readSnapshot(store);
  var quote = stored?.quote;
  var outcome = WidgetRefreshOutcome.signedOut;
  if (quote?.day != todayKey) {
    final container = ProviderContainer(overrides: overrides);
    try {
      final api = HttpQuotesApi(
        AuthenticatedTransport(
          transport: container.read(apiTransportProvider),
          tokens: const _NoSession(),
        ),
      );
      final daily = await api.quoteOfDay(parseDateKey(todayKey));
      quote = WidgetQuote.fromQuote(daily.quote, day: daily.date);
    } on ApiException catch (e) {
      // 401 (the public read is not live yet) or 404 (no quotes): nothing
      // to retry soon. Offline / server errors: retry later.
      if (e.status != 401 && e.status != 404) {
        developer.log('Anonymous quote fetch failed: $e', name: 'WidgetBridge');
        outcome = WidgetRefreshOutcome.retryLater;
      }
    } finally {
      container.dispose();
    }
  }
  final next = buildWidgetSnapshot(
    signedIn: false,
    today: now,
    dueToday: const [],
    log: const CompletionLog.empty(),
    now: now,
  ).copyWith(quote: quote);
  if (stored == null || !stored.sameContentAs(next)) await _write(store, next);
  return outcome;
}

/// No session: [AuthenticatedTransport] then sends `allowAnonymous`
/// requests without a token.
class _NoSession implements AccessTokenProvider {
  const _NoSession();

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) async => null;
}
