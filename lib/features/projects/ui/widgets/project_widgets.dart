/// Small building blocks of the Projects UI, shared by the list, the
/// details and the target editor (and reusable by the calendar task:
/// [projectColor], [TargetStatusChip], [PlanProgressBar], [SessionTile],
/// [OverlapMessageCard]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../habits/widgets/check_in_button.dart';
import '../../domain/overlap.dart';
import '../../models/session.dart';
import '../../models/target.dart';
import '../../projects_providers.dart';

/// A stable, bright colour per project (derived from its id, so it is the
/// same on every device and platform; projects have no stored colour).
Color projectColor(String projectId) {
  const colors = [
    Color(0xFF7C4DFF), // grape
    Color(0xFFFF6B6B), // coral
    Color(0xFF2EC4B6), // mint
    Color(0xFFFF8C42), // tangerine
    Color(0xFF4361EE), // ocean
    Color(0xFFF15BB5), // bubblegum
    Color(0xFF8AC926), // lime
    Color(0xFF4CC9F0), // sky
    Color(0xFFC77DFF), // lavender
    Color(0xFFFFC93C), // sunshine
  ];
  var h = 0;
  for (final c in projectId.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return colors[h % colors.length];
}

/// `Mon 16 Nov`.
String shortDate(DateTime d) => DateFormat('EEE d MMM').format(d);

/// `16 Nov 2026`.
String longDate(DateTime d) => DateFormat('d MMM y').format(d);

String statusLabel(TargetStatus s) => switch (s) {
  TargetStatus.notStarted => 'Not started',
  TargetStatus.inProgress => 'In progress',
  TargetStatus.done => 'Done',
};

IconData statusIcon(TargetStatus s) => switch (s) {
  TargetStatus.notStarted => Icons.radio_button_unchecked_rounded,
  TargetStatus.inProgress => Icons.timelapse_rounded,
  TargetStatus.done => Icons.check_circle_rounded,
};

Color statusColor(TargetStatus s) => switch (s) {
  TargetStatus.notStarted => const Color(0xFF8E8AA8),
  TargetStatus.inProgress => AppColors.flame,
  TargetStatus.done => AppColors.mint,
};

/// A pill with the target's status. With [onChanged] it opens a menu to
/// pick another status (manual only; the app never changes it itself).
class TargetStatusChip extends StatelessWidget {
  final TargetStatus status;
  final ValueChanged<TargetStatus>? onChanged;

  const TargetStatusChip({super.key, required this.status, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            statusLabel(status),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onChanged != null)
            Icon(Icons.expand_more_rounded, size: 16, color: color),
        ],
      ),
    );
    if (onChanged == null) return pill;
    return PopupMenuButton<TargetStatus>(
      tooltip: 'Change status',
      initialValue: status,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final s in TargetStatus.values)
          PopupMenuItem(
            key: ValueKey('status-option-${s.name}'),
            value: s,
            child: Row(
              children: [
                Icon(statusIcon(s), color: statusColor(s)),
                const SizedBox(width: 8),
                Text(statusLabel(s)),
              ],
            ),
          ),
      ],
      child: pill,
    );
  }
}

/// Plan progress (tasks done / total). Display only.
class PlanProgressBar extends StatelessWidget {
  final int done;
  final int total;
  final Color color;

  const PlanProgressBar({
    super.key,
    required this.done,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = total == 0 ? 0.0 : done / total;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: value),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v.clamp(0.0, 1.0),
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          total == 0 ? 'No plan yet' : '$done/$total tasks',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// One session (a consistent action's occurrence) with a bouncy attend
/// button. Only today's and past sessions can be marked ([canAttend]).
class SessionTile extends ConsumerWidget {
  final Session session;
  final String targetTitle;
  final Color color;
  final bool canAttend;

  const SessionTile({
    super.key,
    required this.session,
    required this.targetTitle,
    required this.color,
    required this.canAttend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = session;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(targetTitle, style: theme.textTheme.titleMedium),
                  Text(
                    '${shortDate(s.date)} · ${s.startTime}–${s.endTime}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canAttend)
              CheckInButton(
                key: ValueKey('attend-${s.key}'),
                completed: s.attended,
                color: color,
                size: 44,
                semanticLabel: s.attended ? 'Unmark attended' : 'Mark attended',
                onPressed: () => ref
                    .read(projectServiceProvider)
                    .setSessionAttended(s.actionId, s.date, !s.attended),
              )
            else
              Tooltip(
                message: 'You can mark it on the day',
                child: Icon(
                  Icons.schedule_rounded,
                  key: ValueKey('upcoming-${s.key}'),
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The blocking overlap message (from [ActionOverlapException.message]).
class OverlapMessageCard extends StatelessWidget {
  final String message;
  final String title;

  const OverlapMessageCard({
    super.key,
    required this.message,
    this.title = 'Time clash: not saved',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_busy_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live clash preview for the action form: every clash with its target,
/// project, times and first date.
class ClashList extends StatelessWidget {
  final List<ActionClash> clashes;

  const ClashList({super.key, required this.clashes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('live-clashes'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.flame.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.flame),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Overlaps ${clashes.length == 1 ? 'another time block' : '${clashes.length} time blocks'}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final c in clashes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• “${c.target.title}”'
                '${c.project == null ? '' : ' (${c.project!.name})'}: '
                '${describeRecurrence(c.action.recurrence)} '
                '${c.action.startTime}–${c.action.endTime}, '
                'first on ${shortDate(c.firstDate)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows a refused target change (an [ActionOverlapException]) in a dialog.
Future<void> showOverlapDialog(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('overlap-dialog'),
        icon: const Icon(Icons.event_busy_rounded),
        title: const Text('That would clash'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

/// Asks a yes/no question; `true` when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-dialog-ok'),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

/// Asks for a single line of text (project name, task title); `null` when
/// cancelled. Empty input is refused in place.
Future<String?> textDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _TextDialog(
      title: title,
      label: label,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initial;
  final String confirmLabel;

  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Please type something');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('text-dialog-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: widget.label, errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('text-dialog-ok'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// A rounded section title in Fredoka.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleLarge),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A muted one-line note.
class NoteText extends StatelessWidget {
  final String text;

  const NoteText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
