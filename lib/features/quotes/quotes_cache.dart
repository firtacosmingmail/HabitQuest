import 'dart:convert';

import '../../core/utils/dates.dart';
import '../../data/models/quote.dart';
import '../../data/sync/string_store.dart';

/// The device copy of today's quote and of the saved (loved) quotes, so
/// both show offline (hive box [boxName]; memory in tests).
///
/// Entries belong to one user ([owner]): loved flags are per user, so the
/// cache is cleared when another user reads it.
class QuotesCache {
  static const boxName = 'quotes_cache';

  static const _ownerKey = 'owner';
  static const _todayKey = 'today';
  static const _lovedKey = 'loved';

  final StringStore _store;

  QuotesCache(this._store);

  String? get owner => _store.get(_ownerKey);

  /// Clears everything when [userId] is not the cache's owner, then makes
  /// [userId] the owner.
  Future<void> claim(String userId) async {
    if (owner == userId) return;
    await _store.clear();
    await _store.put(_ownerKey, userId);
  }

  /// Whether the cache can be read for [userId] (same owner).
  bool belongsTo(String userId) => owner == userId;

  /// The cached quote of the day, whatever its date.
  DailyQuote? get dailyQuote {
    final raw = _store.get(_todayKey);
    if (raw == null) return null;
    try {
      return DailyQuote.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// The cached quote of the day if it is the one for [date].
  DailyQuote? dailyQuoteFor(DateTime date) {
    final q = dailyQuote;
    return q != null && dateKey(q.date) == dateKey(date) ? q : null;
  }

  Future<void> saveDailyQuote(DailyQuote quote) =>
      _store.put(_todayKey, jsonEncode(quote.toJson()));

  /// The cached saved quotes (newest love first), or `null` if never
  /// loaded.
  List<Quote>? get lovedQuotes {
    final raw = _store.get(_lovedKey);
    if (raw == null) return null;
    try {
      return [
        for (final q in jsonDecode(raw) as List)
          Quote.fromJson(q as Map<String, dynamic>),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLovedQuotes(List<Quote> quotes) => _store.put(
    _lovedKey,
    jsonEncode([for (final q in quotes) q.toJson()]),
  );

  Future<void> clear() => _store.clear();
}
