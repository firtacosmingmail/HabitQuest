import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_routes.dart';
import '../../core/widgets/message_view.dart';
import '../../data/remote/api_exception.dart';
import 'quotes_providers.dart';
import 'widgets/quote_widgets.dart';

/// Today's quote for signed-out users ([AppRoutes.publicQuote]), e.g. after
/// tapping the Daily quote widget. The only screen the auth gate allows
/// while signed out.
///
/// * The quote is read without a token (cached on the device, offline too).
/// * The heart sends the user to the login screen and remembers the quote
///   (see `toggleQuoteLove`).
/// * Back (system and app bar) goes to the login screen: this screen is
///   often the only page on the stack, so a plain pop would leave the app.
class PublicQuoteScreen extends ConsumerStatefulWidget {
  const PublicQuoteScreen({super.key});

  @override
  ConsumerState<PublicQuoteScreen> createState() => _PublicQuoteScreenState();
}

class _PublicQuoteScreenState extends ConsumerState<PublicQuoteScreen> {
  @override
  void initState() {
    super.initState();
    // A love started earlier and abandoned (the user came back here instead
    // of signing in) must not fire on a later, unrelated sign-in.
    Future.microtask(() {
      if (mounted) ref.read(pendingQuoteLoveProvider.notifier).clear();
    });
  }

  void _toLogin() => context.go(AppRoutes.login);

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayQuoteProvider);
    final daily = today.value;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toLogin();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            key: const ValueKey('public-quote-back'),
            onPressed: _toLogin,
          ),
          title: const Text('Quote of the day'),
        ),
        body: ListView(
          key: const ValueKey('public-quote'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (daily != null)
              QuoteHero(
                quote: daily.quote,
                title: 'Today · ${DateFormat('EEE, MMM d').format(daily.date)}',
                keyPrefix: 'public',
              )
            else if (today.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              MessageView(
                key: const ValueKey('public-quote-unavailable'),
                emoji: today.hasError ? '📡' : '💭',
                title: today.hasError
                    ? "Couldn't load today's quote"
                    : 'No quotes yet',
                message:
                    today.hasError &&
                        today.error is ApiException &&
                        (today.error as ApiException).isNetwork
                    ? "You're offline. Connect to see today's quote."
                    : 'Check back soon for a daily dose of inspiration.',
                action: today.hasError
                    ? TextButton(
                        onPressed: () =>
                            ref.read(todayQuoteProvider.notifier).refresh(),
                        child: const Text('Retry'),
                      )
                    : null,
              ),
            const SizedBox(height: 24),
            Text(
              'Sign in to save your favourite quotes and track your habits.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('public-quote-sign-in'),
              onPressed: _toLogin,
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
