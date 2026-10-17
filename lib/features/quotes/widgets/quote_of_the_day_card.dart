import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../quotes_providers.dart';
import 'quote_widgets.dart';

/// "Quote of the day" at the top of the Habits tab, with a heart toggle.
/// Tapping it opens the Quotes screen. Renders nothing while there is no
/// quote to show (first load, offline without a cached quote, signed out,
/// no quotes on the server).
class QuoteOfTheDayCard extends ConsumerWidget {
  const QuoteOfTheDayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(todayQuoteProvider).value;
    if (daily == null) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('quote-of-the-day-card'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: QuoteHero(
        quote: daily.quote,
        title: 'Quote of the day',
        keyPrefix: 'card',
        onTap: () => context.push(AppRoutes.quotes),
      ),
    );
  }
}
