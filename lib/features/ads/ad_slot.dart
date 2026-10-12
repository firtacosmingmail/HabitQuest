import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'ad_placement.dart';
import 'ad_service.dart';

/// An ad in [placement], provided by [adServiceProvider]. Renders nothing
/// on web, in tests (unless faked) and whenever no ad is available.
class AdSlot extends ConsumerWidget {
  final AdPlacement placement;

  const AdSlot({super.key, required this.placement});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(adServiceProvider).buildAd(context, placement);
}

/// The look shared by every visible ad: about 85% of the available width
/// (visibly narrower than the habit cards), centred, rounded in the playful
/// theme, with a small "Ad" label on top.
class AdFrame extends StatelessWidget {
  /// Fraction of the available width the frame takes.
  static const widthFactor = 0.85;

  /// Inner padding around the ad content.
  static const padding = 8.0;

  /// Width left for the ad itself inside a frame laid out in [maxWidth].
  static double contentWidth(double maxWidth) =>
      maxWidth * widthFactor - 2 * padding;

  final Widget child;

  const AdFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Semantics(
          container: true,
          label: 'Advertisement',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      key: const ValueKey('ad-label'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Ad',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: Center(child: child),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
