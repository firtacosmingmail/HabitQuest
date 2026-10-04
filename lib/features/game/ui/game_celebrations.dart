import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../game_events.dart';
import '../game_providers.dart';
import 'confetti.dart';
import 'mascot.dart';

/// App-wide celebrations for [GameEvent]s, mounted once around the router
/// (`MaterialApp.router(builder: …)` in `app.dart`) so they show on every
/// screen, including routes pushed above the shell.
///
/// * [XpGained] → a floating "+N XP" that rises and fades.
/// * [XpLost] → nothing (quietly reflected by the profile).
/// * [LevelUp] → confetti + a level-up card with the new title and mascot.
/// * [AchievementUnlocked] → a toast with the badge emoji and name.
///
/// Events are queued and shown one at a time. With
/// `MediaQuery.disableAnimations` the confetti is skipped and the rest
/// appear without motion. Everything runs on [AnimationController]s (no
/// timers), so widget tests can settle.
class GameCelebrations extends ConsumerStatefulWidget {
  final Widget child;

  const GameCelebrations({super.key, required this.child});

  @override
  ConsumerState<GameCelebrations> createState() => _GameCelebrationsState();
}

class _GameCelebrationsState extends ConsumerState<GameCelebrations> {
  StreamSubscription<GameEvent>? _sub;
  final _queue = Queue<GameEvent>();
  GameEvent? _current;
  int _seq = 0;
  int? _confettiSeq;

  @override
  void initState() {
    super.initState();
    // Initialise the profile at launch (while the app root builds) so the
    // first widget that watches it later, e.g. the level chip after a
    // navigation, does not create it mid-frame.
    ref.listenManual(gameProfileProvider, (_, _) {});
    ref.listenManual<Stream<GameEvent>>(gameEventsProvider, (_, stream) {
      _sub?.cancel();
      _sub = stream.listen(_onEvent);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(GameEvent event) {
    if (event is XpLost || !mounted) return;
    _queue.add(event);
    _showNext();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _showNext() {
    if (_current != null || _queue.isEmpty || !mounted) return;
    final reduce = _reduceMotion;
    setState(() {
      _current = _queue.removeFirst();
      _seq++;
      if (_current is LevelUp && !reduce) _confettiSeq = _seq;
    });
  }

  void _done() {
    if (!mounted) return;
    setState(() => _current = null);
    _showNext();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = _reduceMotion;
    final current = _current;
    return Stack(
      children: [
        widget.child,
        if (current != null)
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: switch (current) {
                XpGained(:final amount) => XpFloat(
                  key: ValueKey('celebration-$_seq'),
                  amount: amount,
                  reduceMotion: reduce,
                  onDone: _done,
                ),
                LevelUp(:final newLevel, :final title) => LevelUpDialog(
                  key: ValueKey('celebration-$_seq'),
                  level: newLevel,
                  title: title,
                  reduceMotion: reduce,
                  onClose: _done,
                ),
                AchievementUnlocked(:final achievement) => AchievementToast(
                  key: ValueKey('celebration-$_seq'),
                  emoji: achievement.emoji,
                  name: achievement.name,
                  reduceMotion: reduce,
                  onDone: _done,
                ),
                XpLost() => const SizedBox.shrink(),
              },
            ),
          ),
        if (_confettiSeq case final seq?)
          Positioned.fill(
            child: ConfettiBurst(
              key: ValueKey('confetti-$seq'),
              onDone: () {
                if (mounted && _confettiSeq == seq) {
                  setState(() => _confettiSeq = null);
                }
              },
            ),
          ),
      ],
    );
  }
}

/// A one-shot controller that calls [onDone] when it completes. Uses
/// [AnimationBehavior.preserve] so the display time is kept even when the
/// platform asks to reduce animations (the motion itself is skipped).
AnimationController _oneShot(
  TickerProvider vsync,
  Duration duration,
  VoidCallback onDone,
) {
  final c = AnimationController(
    vsync: vsync,
    duration: duration,
    animationBehavior: AnimationBehavior.preserve,
  );
  c.addStatusListener((s) {
    if (s == AnimationStatus.completed) onDone();
  });
  return c;
}

/// "+N XP" that rises and fades.
class XpFloat extends StatefulWidget {
  final int amount;
  final bool reduceMotion;
  final VoidCallback onDone;

  const XpFloat({
    super.key,
    required this.amount,
    required this.onDone,
    this.reduceMotion = false,
  });

  @override
  State<XpFloat> createState() => _XpFloatState();
}

class _XpFloatState extends State<XpFloat> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // Created eagerly: with reduced motion the build never touches it, but
    // it still times how long the celebration stays on screen.
    _c = _oneShot(this, const Duration(milliseconds: 1100), widget.onDone)
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      '+${widget.amount} XP',
      key: const ValueKey('xp-float'),
      style: theme.textTheme.headlineMedium?.copyWith(
        color: AppColors.sunshine,
        fontWeight: FontWeight.w900,
        shadows: const [
          Shadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
    );
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.35),
        child: widget.reduceMotion
            ? label
            : AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final v = _c.value;
                  final rise = Curves.easeOut.transform(v);
                  final opacity = v < 0.6 ? 1.0 : 1 - (v - 0.6) / 0.4;
                  final pop = Curves.easeOutBack.transform(
                    (v * 4).clamp(0.0, 1.0),
                  );
                  return Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -80 * rise),
                      child: Transform.scale(
                        scale: 0.6 + 0.4 * pop,
                        child: child,
                      ),
                    ),
                  );
                },
                child: label,
              ),
      ),
    );
  }
}

/// A banner sliding in from the top: emoji, "Achievement unlocked!", name.
class AchievementToast extends StatefulWidget {
  final String emoji;
  final String name;
  final bool reduceMotion;
  final VoidCallback onDone;

  const AchievementToast({
    super.key,
    required this.emoji,
    required this.name,
    required this.onDone,
    this.reduceMotion = false,
  });

  @override
  State<AchievementToast> createState() => _AchievementToastState();
}

class _AchievementToastState extends State<AchievementToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // Created eagerly: with reduced motion the build never touches it, but
    // it still times how long the celebration stays on screen.
    _c = _oneShot(this, const Duration(milliseconds: 2800), widget.onDone)
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final card = Container(
      key: const ValueKey('achievement-toast'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.sunshine, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Achievement unlocked!',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  widget.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: widget.reduceMotion
              ? card
              : AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) {
                    final v = _c.value;
                    final double hidden;
                    if (v < 0.12) {
                      hidden = 1 - Curves.easeOutBack.transform(v / 0.12);
                    } else if (v > 0.88) {
                      hidden = Curves.easeIn.transform((v - 0.88) / 0.12);
                    } else {
                      hidden = 0;
                    }
                    return FractionalTranslation(
                      translation: Offset(0, -1.5 * hidden),
                      child: child,
                    );
                  },
                  child: card,
                ),
        ),
      ),
    );
  }
}

/// A modal level-up card drawn in the celebration layer (above every
/// route) with the new level, title and mascot. Waits for the player.
class LevelUpDialog extends StatefulWidget {
  final int level;
  final String title;
  final bool reduceMotion;
  final VoidCallback onClose;

  const LevelUpDialog({
    super.key,
    required this.level,
    required this.title,
    required this.onClose,
    this.reduceMotion = false,
  });

  @override
  State<LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends State<LevelUpDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: widget.reduceMotion ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final card = Container(
      key: const ValueKey('level-up-dialog'),
      margin: const EdgeInsets.all(32),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius * 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MascotAvatar(title: widget.title, size: 110),
          const SizedBox(height: 16),
          Text('Level up!', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Level ${widget.level}',
            style: theme.textTheme.titleLarge?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 8),
          Text(
            'You are now a ${widget.title}!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('level-up-dismiss'),
            onPressed: widget.onClose,
            child: const Text('Awesome!'),
          ),
        ],
      ),
    );
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: 'Level up',
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => ModalBarrier(
              dismissible: false,
              color: Colors.black.withValues(
                alpha: 0.5 * _c.value.clamp(0.0, 1.0),
              ),
            ),
          ),
          Center(
            child: widget.reduceMotion
                ? card
                : ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _c,
                      curve: Curves.elasticOut,
                    ),
                    child: card,
                  ),
          ),
        ],
      ),
    );
  }
}
