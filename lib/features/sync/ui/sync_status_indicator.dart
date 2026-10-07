import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/providers.dart';
import '../sync_providers.dart';

/// "5 min ago"-style label for the last sync.
String lastSyncLabel(DateTime? last, DateTime now) {
  if (last == null) return 'never';
  final d = now.difference(last);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return DateFormat.MMMd().format(last);
}

/// Emoji, label and colour for a status (shared by the chip and the Quest
/// card).
(String, String, Color) describeSync(SyncStatus s, ColorScheme scheme) =>
    switch (s.phase) {
      SyncPhase.synced => ('☁️', 'Synced', AppColors.mint),
      SyncPhase.syncing => ('🔄', 'Syncing…', scheme.primary),
      SyncPhase.offline => (
        '📴',
        s.pending > 0 ? 'Offline · ${s.pending} waiting' : 'Offline',
        scheme.outline,
      ),
      SyncPhase.error => ('⚠️', 'Sync hiccup', AppColors.coral),
      SyncPhase.signedOut => ('💤', 'Not syncing', scheme.outline),
      SyncPhase.idle => (
        '☁️',
        s.pending > 0 ? '${s.pending} to sync' : 'Ready to sync',
        scheme.outline,
      ),
    };

/// A small round badge showing the sync state as an emoji (synced ☁️ /
/// syncing 🔄 / offline 📴 / error ⚠️), with the pending-change count, and
/// the label + last sync time in its tooltip and semantics. Tap to sync now.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final now = ref.watch(clockProvider)();
    return SyncStatusChip(
      status: status,
      now: now,
      onTap:
          status.phase == SyncPhase.signedOut ||
              status.phase == SyncPhase.syncing
          ? null
          : () => ref.read(syncControllerProvider.notifier).syncNow(),
    );
  }
}

/// The presentational part of [SyncStatusIndicator].
class SyncStatusChip extends StatelessWidget {
  final SyncStatus status;
  final DateTime now;
  final VoidCallback? onTap;

  const SyncStatusChip({
    super.key,
    required this.status,
    required this.now,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (emoji, label, color) = describeSync(status, theme.colorScheme);
    final last = 'Last sync: ${lastSyncLabel(status.lastSyncedAt, now)}';
    final details = status.message == null ? last : '${status.message}\n$last';
    final showBadge = status.pending > 0 && status.phase != SyncPhase.synced;
    return Tooltip(
      message: '$label\n$details',
      child: Semantics(
        button: onTap != null,
        label: '$label. $details',
        excludeSemantics: true,
        child: Material(
          key: const ValueKey('sync-indicator'),
          color: color.withValues(alpha: 0.14),
          shape: CircleBorder(side: BorderSide(color: color, width: 1.5)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 34,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, a) =>
                        ScaleTransition(scale: a, child: child),
                    child: status.phase == SyncPhase.syncing
                        ? _Spinning(
                            key: const ValueKey('syncing'),
                            child: Text(emoji),
                          )
                        : Text(
                            emoji,
                            key: ValueKey(status.phase),
                            style: const TextStyle(fontSize: 15),
                          ),
                  ),
                  if (showBadge)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        key: const ValueKey('sync-pending-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.sunshine,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.pending > 99 ? '99+' : '${status.pending}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
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

/// Slowly spins its child while syncing (static when animations are off).
class _Spinning extends StatefulWidget {
  final Widget child;

  const _Spinning({super.key, required this.child});

  @override
  State<_Spinning> createState() => _SpinningState();
}

class _SpinningState extends State<_Spinning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    reduce ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _c, child: widget.child);
}

/// Quest tab card: status, last sync time, refused changes and a big
/// "Sync now" button.
class SyncNowCard extends ConsumerWidget {
  const SyncNowCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final (emoji, label, color) = describeSync(status, theme.colorScheme);
    final busy = status.phase == SyncPhase.syncing;
    final canSync = status.phase != SyncPhase.signedOut && !busy;
    return Card(
      key: const ValueKey('sync-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: 0.18),
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleMedium),
                  Text(
                    'Last sync: ${lastSyncLabel(status.lastSyncedAt, now)}'
                    '${status.message != null ? '\n${status.message}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('sync-now-button'),
              onPressed: canSync
                  ? () => ref.read(syncControllerProvider.notifier).syncNow()
                  : null,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
            ),
          ],
        ),
      ),
    );
  }
}
