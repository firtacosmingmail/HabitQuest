/// Riverpod wiring for quotes: the quote of the day, past days' quotes and
/// the user's saved (loved) quotes, with a device cache and optimistic love
/// toggles.
///
/// Reuse: [todayQuoteProvider] gives today's [DailyQuote] (`quote.text`,
/// `quote.author`) for the user's *local* calendar day, from the device
/// cache first, then from the server.
///
/// Tests override [quotesApiProvider] (with `FakeQuotesApi`) and, to check
/// persistence, [quotesCacheProvider] (with a `QuotesCache` over a
/// `MemoryStringStore`). The app overrides [quotesCacheProvider] in
/// `main.dart` with the hive box [QuotesCache.boxName].
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dates.dart';
import '../../data/remote/api_exception.dart';
import '../../data/remote/quotes_api.dart';
import '../../data/sync/string_store.dart';
import '../../domain/providers.dart';
import '../auth/auth_providers.dart';
import 'quotes_cache.dart';

export '../../data/remote/quotes_api.dart';
export '../auth/auth_providers.dart' show quotesApiProvider;
export 'quotes_cache.dart';

/// Number of past days the Quotes screen lists.
const quoteHistoryDays = 30;

/// No automatic retries: the controllers fall back to the cache and the
/// screens offer a manual retry / pull-to-refresh.
Duration? _noRetry(int _, Object _) => null;

/// The device cache. In memory unless overridden (`main.dart` opens the
/// hive box [QuotesCache.boxName]).
final quotesCacheProvider = Provider<QuotesCache>(
  (ref) => QuotesCache(MemoryStringStore()),
);

/// The signed-in user's id, or `null` when signed out. Only changes when
/// the user changes (not on token refreshes).
final quotesUserIdProvider = Provider<String?>(
  (ref) => ref.watch(
    authControllerProvider.select(
      (auth) => auth is SignedIn ? auth.session.user.id : null,
    ),
  ),
);

// Quote of the day -----------------------------------------------------------

/// Today's quote for the local calendar day ([todayProvider]); `null` when
/// signed out or when the server has no quotes at all (404).
///
/// Shows the cached copy for today right away (offline too) and refreshes
/// it from the server in the background. Rebuilds when the day changes.
final todayQuoteProvider =
    AsyncNotifierProvider<TodayQuoteController, DailyQuote?>(
      TodayQuoteController.new,
      retry: _noRetry,
    );

class TodayQuoteController extends AsyncNotifier<DailyQuote?> {
  @override
  Future<DailyQuote?> build() async {
    final userId = ref.watch(quotesUserIdProvider);
    if (userId == null) return null;
    final day = ref.watch(todayProvider);
    final cache = ref.read(quotesCacheProvider);
    final cached = cache.belongsTo(userId) ? cache.dailyQuoteFor(day) : null;
    if (cached != null) {
      unawaited(_refreshQuietly(userId, day));
      return cached;
    }
    return _fetch(userId, day);
  }

  /// Reloads from the server; keeps the current quote if that fails.
  Future<void> refresh() async {
    final userId = ref.read(quotesUserIdProvider);
    if (userId == null) return;
    final day = ref.read(todayProvider);
    if (!state.hasValue || state.value == null) {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() => _fetch(userId, day));
    } else {
      await _refreshQuietly(userId, day);
    }
  }

  /// Sets the loved flag of today's quote (state and cache) if it is
  /// [quoteId].
  Future<void> applyLoved(String quoteId, bool loved) async {
    final current = state.value;
    if (current == null || current.quote.id != quoteId) return;
    final updated = current.withQuote(current.quote.withLoved(loved));
    state = AsyncData(updated);
    await _save(updated);
  }

  Future<DailyQuote?> _fetch(String userId, DateTime day) async {
    try {
      final quote = await ref.read(quotesApiProvider).quoteOfDay(day);
      await _save(quote, userId: userId);
      return quote;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> _refreshQuietly(String userId, DateTime day) async {
    try {
      final quote = await _fetch(userId, day);
      if (ref.mounted && ref.read(quotesUserIdProvider) == userId) {
        state = AsyncData(quote);
      }
    } catch (_) {
      // Offline or server error: keep what is shown.
    }
  }

  Future<void> _save(DailyQuote? quote, {String? userId}) async {
    final user = userId ?? ref.read(quotesUserIdProvider);
    if (quote == null || user == null) return;
    final cache = ref.read(quotesCacheProvider);
    await cache.claim(user);
    await cache.saveDailyQuote(quote);
  }
}

// Past days ------------------------------------------------------------------

/// The scheduled quotes of the [quoteHistoryDays] local days before today,
/// newest day first (`GET /quotes?from=&to=`, local dates so the list
/// lines up with today's local quote). Not cached.
final pastQuotesProvider = FutureProvider.autoDispose<List<Quote>>((
  ref,
) async {
  final userId = ref.watch(quotesUserIdProvider);
  if (userId == null) return const [];
  final today = ref.watch(todayProvider);
  final history = await ref
      .read(quotesApiProvider)
      .quotesBetween(addDays(today, -quoteHistoryDays), addDays(today, -1));
  return [
    for (final q in history.items)
      if (q.day == null || q.day!.isBefore(today)) q,
  ];
}, retry: _noRetry);

// Saved quotes ---------------------------------------------------------------

/// The user's loved quotes, newest love first. Cached on the device; the
/// cached list shows first (offline too) and is refreshed from the server.
final savedQuotesProvider =
    AsyncNotifierProvider<SavedQuotesController, List<Quote>>(
      SavedQuotesController.new,
      retry: _noRetry,
    );

class SavedQuotesController extends AsyncNotifier<List<Quote>> {
  @override
  Future<List<Quote>> build() async {
    final userId = ref.watch(quotesUserIdProvider);
    if (userId == null) return const [];
    final cache = ref.read(quotesCacheProvider);
    final cached = cache.belongsTo(userId) ? cache.lovedQuotes : null;
    if (cached != null) {
      unawaited(_refreshQuietly(userId));
      return cached;
    }
    return _fetch(userId);
  }

  /// Reloads from the server; keeps the current list if that fails.
  Future<void> refresh() async {
    final userId = ref.read(quotesUserIdProvider);
    if (userId == null || state.isLoading) return;
    if (!state.hasValue) {
      state = const AsyncLoading();
      state = await AsyncValue.guard(() => _fetch(userId));
    } else {
      await _refreshQuietly(userId);
    }
  }

  Future<List<Quote>> _fetch(String userId) async {
    final quotes = await ref.read(quotesApiProvider).lovedQuotes();
    await _save(quotes, userId: userId);
    return quotes;
  }

  Future<void> _refreshQuietly(String userId) async {
    try {
      final quotes = await _fetch(userId);
      if (ref.mounted && ref.read(quotesUserIdProvider) == userId) {
        state = AsyncData(quotes);
      }
    } catch (_) {
      // Offline or server error: keep what is shown.
    }
  }

  /// Puts [quote] first (loved) or removes it (unloved), without the
  /// server. When re-adding, [index] restores its previous position.
  void applyLocal(Quote quote, bool loved, {int index = 0}) {
    final current = state.value;
    if (current == null) return;
    final without = [
      for (final q in current)
        if (q.id != quote.id) q,
    ];
    if (loved) {
      without.insert(index.clamp(0, without.length), quote);
    }
    state = AsyncData(without);
  }

  /// Replaces the entry of [quote] (e.g. with the server's `lovedAt`).
  void replace(Quote quote) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final q in current) q.id == quote.id ? quote : q,
    ]);
  }

  /// Writes the current list to the device cache.
  Future<void> persist() async {
    final current = state.value;
    if (current != null) await _save(current);
  }

  Future<void> _save(List<Quote> quotes, {String? userId}) async {
    final user = userId ?? ref.read(quotesUserIdProvider);
    if (user == null) return;
    final cache = ref.read(quotesCacheProvider);
    await cache.claim(user);
    await cache.saveLovedQuotes(quotes);
  }
}

// Loved state ----------------------------------------------------------------

/// Love state set on this device, by quote id. It wins over the `loved`
/// flag of quotes fetched earlier, so the card, the Quotes screen and the
/// Saved screen always agree. Cleared when the user changes.
final quoteLoveOverridesProvider =
    NotifierProvider<QuoteLoveOverrides, Map<String, bool>>(
      QuoteLoveOverrides.new,
    );

class QuoteLoveOverrides extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() {
    ref.watch(quotesUserIdProvider);
    return const {};
  }

  void set(String quoteId, bool loved) =>
      state = {...state, quoteId: loved};
}

/// Whether [quote] is loved, taking local toggles into account.
final quoteLovedProvider = Provider.autoDispose.family<bool, Quote>(
  (ref, quote) =>
      ref.watch(quoteLoveOverridesProvider.select((m) => m[quote.id])) ??
      quote.loved,
);

/// Loves / unloves quotes: optimistic everywhere at once, rolled back if
/// the server call fails.
final quoteLoveControllerProvider = Provider<QuoteLoveController>(
  QuoteLoveController.new,
);

class QuoteLoveController {
  final Ref ref;
  final _pending = <String>{};

  QuoteLoveController(this.ref);

  /// Whether a love / unlove of [quoteId] is in flight.
  bool isPending(String quoteId) => _pending.contains(quoteId);

  /// Flips the love state of [quote]. Returns the new state, or `null` if
  /// a toggle of that quote is already in flight. Throws [ApiException]
  /// after rolling back.
  Future<bool?> toggle(Quote quote) =>
      setLoved(quote, !ref.read(quoteLovedProvider(quote)));

  /// Loves or unloves [quote]: updates the card, the Quotes screen and the
  /// Saved list immediately, then calls the server; on failure restores the
  /// previous state everywhere and rethrows.
  Future<bool?> setLoved(Quote quote, bool loved) async {
    if (!_pending.add(quote.id)) return null;
    final overrides = ref.read(quoteLoveOverridesProvider.notifier);
    final saved = ref.read(savedQuotesProvider.notifier);
    final today = ref.read(todayQuoteProvider.notifier);
    final previous = ref.read(quoteLovedProvider(quote));
    final savedBefore = ref.read(savedQuotesProvider).value ?? const [];
    final previousIndex = savedBefore.indexWhere((q) => q.id == quote.id);
    final previousEntry = previousIndex < 0 ? null : savedBefore[previousIndex];

    overrides.set(quote.id, loved);
    saved.applyLocal(
      quote.withLoved(
        loved,
        lovedAt: quote.lovedAt ?? ref.read(clockProvider)().toUtc(),
      ),
      loved,
    );
    try {
      final api = ref.read(quotesApiProvider);
      if (loved) {
        saved.replace(await api.love(quote.id));
      } else {
        await api.unlove(quote.id);
      }
      await today.applyLoved(quote.id, loved);
      await saved.persist();
      return loved;
    } catch (_) {
      overrides.set(quote.id, previous);
      if (previousEntry != null) {
        saved.applyLocal(previousEntry, true, index: previousIndex);
      } else {
        saved.applyLocal(quote, false);
      }
      rethrow;
    } finally {
      _pending.remove(quote.id);
    }
  }
}
