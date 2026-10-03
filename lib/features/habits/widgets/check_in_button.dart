import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';

/// A big round check-in button that bounces and gives haptic feedback when
/// tapped. [onPressed] `null` renders it disabled (e.g. in a preview).
class CheckInButton extends StatefulWidget {
  final bool completed;
  final Color color;
  final VoidCallback? onPressed;
  final double size;
  final String? semanticLabel;

  const CheckInButton({
    super.key,
    required this.completed,
    required this.color,
    required this.onPressed,
    this.size = 60,
    this.semanticLabel,
  });

  @override
  State<CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<CheckInButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.28,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.28,
        end: 0.9,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.9,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 35,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.completed) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    _controller.forward(from: 0);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color;
    final done = widget.completed;
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF1B1B1F);
    final enabled = widget.onPressed != null;

    return Semantics(
      button: true,
      toggled: done,
      enabled: enabled,
      label: widget.semanticLabel ?? (done ? 'Undo check-in' : 'Check in'),
      excludeSemantics: true,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? color : color.withValues(alpha: 0.08),
            border: Border.all(
              color: done ? color : color.withValues(alpha: 0.55),
              width: 3,
            ),
            boxShadow: done
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? _handleTap : null,
              splashColor: AppColors.sunshine.withValues(alpha: 0.4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  Icons.check_rounded,
                  key: ValueKey(done),
                  size: widget.size * 0.55,
                  color: done
                      ? onColor
                      : (enabled
                            ? color.withValues(alpha: 0.5)
                            : scheme.outlineVariant),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
