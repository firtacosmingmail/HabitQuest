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
/// the server has no quotes at all (404). Signed out it is read without a
/// token (`loved` always `false`) and cached under
/// [QuotesCache.anonymousOwner]; if that read fails (offline, or a backend
/// that still answers 401) the last cached quote is shown instead.
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
    final owner = _owner(ref.watch(quotesUserIdProvider));
    final day = ref.watch(todayProvider);
    final cache = ref.read(quotesCacheProvider);
    final cached = cache.belongsTo(owner) ? cache.dailyQuoteFor(day) : null;
    if (cached != null) {
      unawaited(_refreshQuietly(owner, day));
      return cached;
    }
    if (owner == QuotesCache.anonymousOwner) {
      // Signed out: the public read may be refused (401 before the backend
      // allowed it) or offline. Fall back to the last cached quote of any
      // day (it may be the previous user's one) rather than an error.
      try {
        return await _fetch(owner, day);
      } on ApiException {
        final last = cache.dailyQuote;
        if (last != null) return last.withQuote(last.quote.withLoved(false));
        rethrow;
      }
    }
    return _fetch(owner, day);
  }

  /// Reloads from the server; keeps the current quote if that fails.
  Future<void> refresh() async {
    final owner = _owner(ref.read(quotesUserIdProvider));
    final day = ref.read(todayProvider);
    final current = state.value;
    if (current == null || dateKey(current.date) != dateKey(day)) {
      if (current == null) state = const AsyncLoading();
      final next = await AsyncValue.guard(() => _fetch(owner, day));
      if (!ref.mounted) return;
      // Keep an older quote rather than replacing it with an error.
      if (next.hasError && current != null) return;
      state = next;
    } else {
      await _refreshQuietly(owner, day);
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

  Future<DailyQuote?> _fetch(String owner, DateTime day) async {
    try {
      var quote = await ref.read(quotesApiProvider).quoteOfDay(day);
      if (owner == QuotesCache.anonymousOwner) {
        quote = quote.withQuote(quote.quote.withLoved(false));
      }
      await _save(quote, owner: owner);
      return quote;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> _refreshQuietly(String owner, DateTime day) async {
    try {
      final quote = await _fetch(owner, day);
      if (ref.mounted && _owner(ref.read(quotesUserIdProvider)) == owner) {
        state = AsyncData(quote);
      }
    } catch (_) {
      // Offline or server error: keep what is shown.
    }
  }

  Future<void> _save(DailyQuote? quote, {String? owner}) async {
    final user = owner ?? _owner(ref.read(quotesUserIdProvider));
    if (quote == null) return;
    final cache = ref.read(quotesCacheProvider);
    await cache.claim(user);
    await cache.saveDailyQuote(quote);
  }
}

/// The cache owner for [userId] ([QuotesCache.anonymousOwner] signed out).
String _owner(String? userId) => userId ?? QuotesCache.anonymousOwner;

// Past days ------------------------------------------------------------------

/// The scheduled quotes of the [quoteHistoryDays] local days before today,
/// newest day first (`GET /quotes?from=&to=`, local dates so the list
/// lines up with today's local quote). Not cached.
final pastQuotesProvider = FutureProvider.autoDispose<List<Quote>>((ref) async {
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
    state = AsyncData([for (final q in current) q.id == quote.id ? quote : q]);
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

  void set(String quoteId, bool loved) => state = {...state, quoteId: loved};
}

/// A quote the user tried to love while signed out: the heart sent them to
/// the login screen, and the Quotes screen they land on after signing in
/// completes the love ([PendingQuoteLove.take]). In memory only; survives
/// the sign-in (not tied to the user).
final pendingQuoteLoveProvider = NotifierProvider<PendingQuoteLove, Quote?>(
  PendingQuoteLove.new,
);

class PendingQuoteLove extends Notifier<Quote?> {
  @override
  Quote? build() => null;

  void set(Quote quote) => state = quote;

  void clear() => state = null;

  /// Returns the pending quote and clears it.
  Quote? take() {
    final quote = state;
    state = null;
    return quote;
  }
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
    // Only touch the lists that are loaded: reading them would start a
    // fetch.
    final saved = ref.exists(savedQuotesProvider)
        ? ref.read(savedQuotesProvider.notifier)
        : null;
    final previous = ref.read(quoteLovedProvider(quote));
    final savedBefore = saved == null
        ? const <Quote>[]
        : ref.read(savedQuotesProvider).value ?? const <Quote>[];
    final previousIndex = savedBefore.indexWhere((q) => q.id == quote.id);
    final previousEntry = previousIndex < 0 ? null : savedBefore[previousIndex];

    overrides.set(quote.id, loved);
    saved?.applyLocal(
      quote.withLoved(
        loved,
        lovedAt: quote.lovedAt ?? ref.read(clockProvider)().toUtc(),
      ),
      loved,
    );
    try {
      final api = ref.read(quotesApiProvider);
      Quote? lovedQuote;
      if (loved) {
        lovedQuote = await api.love(quote.id);
        saved?.replace(lovedQuote);
      } else {
        await api.unlove(quote.id);
      }
      if (ref.exists(todayQuoteProvider)) {
        await ref.read(todayQuoteProvider.notifier).applyLoved(quote.id, loved);
      }
      if (saved != null) {
        await saved.persist();
      } else {
        await _patchCachedList(quote, lovedQuote);
      }
      return loved;
    } catch (_) {
      overrides.set(quote.id, previous);
      if (previousEntry != null) {
        saved?.applyLocal(previousEntry, true, index: previousIndex);
      } else {
        saved?.applyLocal(quote, false);
      }
      rethrow;
    } finally {
      _pending.remove(quote.id);
    }
  }

  /// Keeps the cached saved list right when the Saved list is not loaded
  /// (e.g. a love from the Habits card), so it is correct offline too.
  Future<void> _patchCachedList(Quote quote, Quote? lovedQuote) async {
    final user = ref.read(quotesUserIdProvider);
    final cache = ref.read(quotesCacheProvider);
    if (user == null || !cache.belongsTo(user)) return;
    final list = cache.lovedQuotes;
    if (list == null) return;
    await cache.saveLovedQuotes([
      ?lovedQuote,
      for (final q in list)
        if (q.id != quote.id) q,
    ]);
  }
}
