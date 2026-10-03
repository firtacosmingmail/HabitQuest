import 'package:flutter/material.dart';

import '../../../core/constants/habit_defaults.dart';
import '../../../core/theme/app_theme.dart';

/// Grid of emoji choices ([HabitDefaults.emojiChoices]). Each item has the
/// key `ValueKey('emoji-<emoji>')`.
class EmojiPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  final Color accent;
  final List<String> choices;

  const EmojiPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.accent,
    this.choices = HabitDefaults.emojiChoices,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in choices)
          _EmojiChoice(
            key: ValueKey('emoji-$e'),
            emoji: e,
            selected: e == selected,
            accent: accent,
            onTap: () => onSelected(e),
          ),
      ],
    );
  }
}

class _EmojiChoice extends StatelessWidget {
  final String emoji;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _EmojiChoice({
    super.key,
    required this.emoji,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusSmall);
    return Semantics(
      selected: selected,
      button: true,
      label: emoji,
      child: AnimatedScale(
        scale: selected ? 1.12 : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: selected
                ? accent.withValues(alpha: 0.22)
                : Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 24, height: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
