import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A gradient flame that grows a little with the streak and pops when the
/// streak changes. Greyed out at 0.
class StreakFlame extends StatelessWidget {
  final int streak;
  final double size;

  const StreakFlame({super.key, required this.streak, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final active = streak > 0;
    // Grows from 1.0x to 1.3x over the first 30 periods.
    final grow = 1 + (streak.clamp(0, 30) / 30) * 0.3;
    final iconSize = size * grow;
    final icon = Icon(
      Icons.local_fire_department_rounded,
      size: iconSize,
      color: active
          ? Colors.white
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
    );
    return SizedBox(
      width: size * 1.3,
      height: size * 1.3,
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(streak),
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: active
              ? ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [AppColors.coral, AppColors.flame, AppColors.sunshine],
                  ).createShader(rect),
                  child: icon,
                )
              : icon,
        ),
      ),
    );
  }
}
