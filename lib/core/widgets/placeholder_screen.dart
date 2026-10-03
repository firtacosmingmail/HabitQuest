import 'package:flutter/material.dart';

/// Temporary body for screens that other tasks will build.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String emoji;
  final String message;
  final List<Widget> actions;

  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.emoji,
    this.message = 'Coming soon!',
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(message,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
