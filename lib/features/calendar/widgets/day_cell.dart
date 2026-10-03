import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/dates.dart';
import '../calendar_month.dart';

/// One day of the month grid: the day number inside a progress ring.
///
/// * tracked days (today or past, something due): a ring filled by
///   done/due, golden glow + ⭐ for Perfect Days;
/// * upcoming days: a faint ring track (no progress);
/// * empty days: just the number.
class DayCell extends StatelessWidget {
  final DayStatus status;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  const DayCell({
    super.key,
    required this.status,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final perfect = status.isPerfect;
    final key = dateKey(status.date);

    final Color numberColor;
    if (perfect) {
      numberColor = const Color(0xFF5A3E00);
    } else if (status.kind == DayKind.upcoming) {
      numberColor = scheme.onSurface.withValues(alpha: 0.45);
    } else if (isToday) {
      numberColor = scheme.primary;
    } else {
      numberColor = scheme.onSurface;
    }

    final label = StringBuffer('${status.date.day}');
    if (isToday) label.write(', today');
    if (status.kind == DayKind.tracked) {
      label.write(', ${status.done} of ${status.due} done');
    } else if (status.kind == DayKind.upcoming) {
      label.write(', ${status.due} due');
    }
    if (perfect) label.write(', Perfect Day');

    return Semantics(
      button: true,
      selected: isSelected,
      label: label.toString(),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('calendar-day-$key'),
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? scheme.primary.withValues(alpha: isDark ? 0.30 : 0.14)
                : Colors.transparent,
            border: isToday
                ? Border.all(color: scheme.primary, width: 2)
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _ring(scheme, isDark),
                ),
              ),
              Text(
                '${status.date.day}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: numberColor,
                  fontWeight:
                      isToday || perfect ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (perfect)
                Positioned(
                  top: -4,
                  right: -2,
                  child: Text(
                    '⭐',
                    key: ValueKey('perfect-day-$key'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(ColorScheme scheme, bool isDark) {
    switch (status.kind) {
      case DayKind.empty:
        return const SizedBox.shrink();
      case DayKind.upcoming:
        return CustomPaint(
          painter: _RingPainter(
            fraction: 0,
            track: scheme.onSurface.withValues(alpha: isDark ? 0.14 : 0.08),
            progress: Colors.transparent,
            dashed: true,
          ),
        );
      case DayKind.tracked:
        if (status.isPerfect) {
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFFFFE08A), AppColors.perfectDay],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.perfectDay
                      .withValues(alpha: isDark ? 0.55 : 0.7),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          );
        }
        return TweenAnimationBuilder<double>(
          tween: Tween(end: status.fraction),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => CustomPaint(
            painter: _RingPainter(
              fraction: value,
              track: AppColors.coral.withValues(alpha: isDark ? 0.30 : 0.20),
              progress: AppColors.success,
            ),
          ),
        );
    }
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color track;
  final Color progress;
  final bool dashed;

  _RingPainter({
    required this.fraction,
    required this.track,
    required this.progress,
    this.dashed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(3.0, size.shortestSide * 0.09);
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    if (dashed) {
      const segments = 12;
      const sweep = 2 * math.pi / segments;
      for (var i = 0; i < segments; i++) {
        canvas.drawArc(arcRect, i * sweep, sweep * 0.55, false, trackPaint);
      }
      return;
    }
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, trackPaint);
    if (fraction <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      trackPaint..color = progress,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.progress != progress ||
      old.dashed != dashed;
}
