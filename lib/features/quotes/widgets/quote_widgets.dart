import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/remote/api_exception.dart';
import '../quotes_providers.dart';

/// The heart toggle of a quote. Optimistic: flips at once, rolls back and
/// shows a snackbar when the server call fails.
///
/// Keyed `<keyPrefix>-love-<quote id>` (e.g. `card-love-q1`).
class QuoteLoveButton extends ConsumerWidget {
  final Quote quote;
  final String keyPrefix;
  final Color? color;

  const QuoteLoveButton({
    super.key,
    required this.quote,
    required this.keyPrefix,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loved = ref.watch(quoteLovedProvider(quote));
    return IconButton(
      key: ValueKey('$keyPrefix-love-${quote.id}'),
      tooltip: loved ? 'Remove from saved quotes' : 'Save this quote',
      isSelected: loved,
      onPressed: () => toggleQuoteLove(context, ref, quote),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          loved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(loved),
          color: loved ? AppColors.coral : color,
        ),
      ),
    );
  }
}

/// Toggles the love of [quote] (see [QuoteLoveController]); shows a
/// snackbar if it failed and was rolled back.
Future<void> toggleQuoteLove(
  BuildContext context,
  WidgetRef ref,
  Quote quote,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(quoteLoveControllerProvider).toggle(quote);
  } catch (e) {
    final offline = e is ApiException && e.isNetwork;
    messenger?.showSnackBar(
      SnackBar(
        key: const ValueKey('quote-love-error'),
        content: Text(
          offline
              ? "You're offline. Your saved quotes did not change."
              : 'Could not update your saved quotes. Please try again.',
        ),
      ),
    );
  }
}

/// A quote as a rounded card: the text, the author and a heart toggle.
class QuoteTile extends StatelessWidget {
  final Quote quote;
  final String keyPrefix;

  /// Optional line above the text (e.g. the date).
  final String? caption;

  const QuoteTile({
    super.key,
    required this.quote,
    required this.keyPrefix,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('$keyPrefix-quote-${quote.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (caption != null) ...[
                    Text(
                      caption!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text('“${quote.text}”', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    quote.attribution,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            QuoteLoveButton(quote: quote, keyPrefix: keyPrefix),
          ],
        ),
      ),
    );
  }
}

/// The big gradient panel used for today's quote (Habits card and Quotes
/// screen).
class QuoteHero extends StatelessWidget {
  final Quote quote;
  final String title;
  final String keyPrefix;
  final VoidCallback? onTap;

  const QuoteHero({
    super.key,
    required this.quote,
    required this.title,
    required this.keyPrefix,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const ink = Colors.white;
    final radius = BorderRadius.circular(AppTheme.radius);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            colors: [AppColors.coral, AppColors.flame],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          key: ValueKey('$keyPrefix-quote-${quote.id}'),
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('💬', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    QuoteLoveButton(
                      quote: quote,
                      keyPrefix: keyPrefix,
                      color: ink,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“${quote.text}”',
                        style: theme.textTheme.titleLarge?.copyWith(color: ink),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        quote.attribution,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
