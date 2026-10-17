import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_routes.dart';
import '../../core/widgets/message_view.dart';
import '../../data/remote/api_exception.dart';
import 'quotes_providers.dart';
import 'widgets/quote_widgets.dart';

/// Quotes screen (`/quotes`): today's quote and the quotes of the past
/// [quoteHistoryDays] days, each with a heart toggle; links to the saved
/// quotes. No ads here.
class QuotesScreen extends ConsumerWidget {
  const QuotesScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(pastQuotesProvider);
    await Future.wait([
      ref.read(todayQuoteProvider.notifier).refresh(),
      ref.read(pastQuotesProvider.future).then((_) {}, onError: (_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayQuoteProvider);
    final past = ref.watch(pastQuotesProvider);
    final daily = today.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotes'),
        actions: [
          IconButton(
            key: const ValueKey('open-saved-quotes'),
            tooltip: 'Saved quotes',
            icon: const Icon(Icons.favorite_rounded),
            onPressed: () => context.push(AppRoutes.savedQuotes),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          key: const ValueKey('quotes-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (daily != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: QuoteHero(
                  quote: daily.quote,
                  title: 'Today · ${_formatDay(daily.date)}',
                  keyPrefix: 'today',
                ),
              )
            else if (today.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (today.hasError)
              _ErrorNote(
                key: const ValueKey('today-quote-error'),
                error: today.error,
                what: "today's quote",
                onRetry: () => ref.read(todayQuoteProvider.notifier).refresh(),
              )
            else
              const MessageView(
                key: ValueKey('no-quotes'),
                emoji: '💭',
                title: 'No quotes yet',
                message: 'Check back soon for a daily dose of inspiration.',
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: OutlinedButton.icon(
                key: const ValueKey('saved-quotes-button'),
                onPressed: () => context.push(AppRoutes.savedQuotes),
                icon: const Icon(Icons.favorite_border_rounded),
                label: const Text('Saved quotes'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text(
                'Past days',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ...past.when(
              skipLoadingOnRefresh: true,
              data: (quotes) => quotes.isEmpty
                  ? [const _Note('No quotes from past days yet.')]
                  : [
                      for (final q in quotes)
                        QuoteTile(
                          quote: q,
                          keyPrefix: 'past',
                          caption: q.day == null ? null : _formatDay(q.day!),
                        ),
                    ],
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [
                _ErrorNote(
                  key: const ValueKey('past-quotes-error'),
                  error: e,
                  what: "past days' quotes",
                  onRetry: () => ref.invalidate(pastQuotesProvider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDay(DateTime day) => DateFormat('EEE, MMM d').format(day);

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final Object? error;
  final String what;
  final VoidCallback onRetry;

  const _ErrorNote({
    super.key,
    required this.error,
    required this.what,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).isNetwork;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Text(
          offline ? '📡' : '🙈',
          style: const TextStyle(fontSize: 26),
        ),
        title: Text(offline ? "You're offline" : "Couldn't load $what"),
        subtitle: Text(
          offline
              ? 'Connect to the internet to see $what.'
              : 'Please try again in a moment.',
        ),
        trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    );
  }
}
