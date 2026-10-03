import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Row of colour swatches ([HabitPalette.colors]). Each swatch has the key
/// `ValueKey('color-<index>')`.
class HabitColorPicker extends StatelessWidget {
  /// Selected `Color.toARGB32()` value.
  final int selectedValue;
  final ValueChanged<int> onSelected;
  final List<Color> colors;

  const HabitColorPicker({
    super.key,
    required this.selectedValue,
    required this.onSelected,
    this.colors = HabitPalette.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < colors.length; i++)
          _Swatch(
            key: ValueKey('color-$i'),
            color: colors[i],
            selected: colors[i].toARGB32() == selectedValue,
            onTap: () => onSelected(colors[i].toARGB32()),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Colour',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: selected ? 44 : 38,
          height: selected ? 44 : 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 3,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10),
            ],
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color: HabitPalette.onColor(color),
                  size: 22,
                )
              : null,
        ),
      ),
    );
  }
}
