import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/message_view.dart';
import '../../data/remote/api_exception.dart';
import 'quotes_providers.dart';
import 'widgets/quote_widgets.dart';

/// Saved quotes (`/quotes/saved`): the loved quotes, newest love first,
/// each with a heart to unlove it. Shows the device copy offline. No ads
/// here.
class SavedQuotesScreen extends ConsumerStatefulWidget {
  const SavedQuotesScreen({super.key});

  @override
  ConsumerState<SavedQuotesScreen> createState() => _SavedQuotesScreenState();
}

class _SavedQuotesScreenState extends ConsumerState<SavedQuotesScreen> {
  @override
  void initState() {
    super.initState();
    // Picks up loves made on other devices (no-op while the first load
    // is running).
    Future.microtask(() {
      if (mounted) ref.read(savedQuotesProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedQuotesProvider);
    final controller = ref.read(savedQuotesProvider.notifier);

    final Widget body;
    if (saved.hasValue) {
      final quotes = saved.requireValue;
      body = quotes.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 48),
                MessageView(
                  key: ValueKey('saved-quotes-empty'),
                  emoji: '💖',
                  title: 'No saved quotes yet',
                  message:
                      'Tap the heart on a quote you love and it will be '
                      'waiting for you here.',
                ),
              ],
            )
          : ListView(
              key: const ValueKey('saved-quotes-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final q in quotes) QuoteTile(quote: q, keyPrefix: 'saved'),
              ],
            );
    } else if (saved.hasError) {
      final e = saved.error;
      final offline = e is ApiException && e.isNetwork;
      body = MessageView(
        key: const ValueKey('saved-quotes-error'),
        emoji: offline ? '📡' : '🙈',
        title: offline ? "You're offline" : "Couldn't load your saved quotes",
        message: offline
            ? 'Your saved quotes show up once we can reach the server.'
            : 'Please try again in a moment.',
        action: FilledButton.icon(
          onPressed: controller.refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Saved quotes')),
      body: RefreshIndicator(onRefresh: controller.refresh, child: body),
    );
  }
}
