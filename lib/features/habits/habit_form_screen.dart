import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/habit_defaults.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/message_view.dart';
import '../../data/models/habit.dart';
import '../../data/models/habit_schedule.dart';
import '../../domain/providers.dart';
import 'widgets/emoji_picker.dart';
import 'widgets/habit_card.dart';
import 'widgets/habit_color_picker.dart';
import 'widgets/schedule_picker.dart';

/// Create (`/habits/new`, [habitId] == null) or edit (`/habits/:id/edit`)
/// a habit.
class HabitFormScreen extends ConsumerStatefulWidget {
  final String? habitId;

  const HabitFormScreen({super.key, this.habitId});

  bool get isEditing => habitId != null;

  @override
  ConsumerState<HabitFormScreen> createState() => _HabitFormScreenState();
}

class _HabitFormScreenState extends ConsumerState<HabitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  Habit? _original;
  String _emoji = HabitDefaults.emoji;
  int _colorValue = HabitPalette.defaultColorValue;
  HabitSchedule? _schedule = const DailySchedule();
  late DateTime _startDate;
  ReminderTime? _reminder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = ref.read(todayProvider);
    final id = widget.habitId;
    if (id != null) {
      final habit = ref.read(habitRepositoryProvider).getHabit(id);
      if (habit != null) {
        _original = habit;
        _nameController.text = habit.name;
        _emoji = habit.emoji;
        _colorValue = habit.colorValue;
        _schedule = habit.schedule;
        _startDate = habit.startDate;
        _reminder = habit.reminderTime;
      }
    }
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Give your habit a name';
    if (name.length > HabitDefaults.maxNameLength) {
      return 'Keep it under ${HabitDefaults.maxNameLength} characters';
    }
    return null;
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.habits);
    }
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    final schedule = _schedule;
    if (!formOk || schedule == null) {
      if (schedule == null) {
        _showSnack('Pick at least one day for the schedule');
      }
      return;
    }
    setState(() => _saving = true);
    final service = ref.read(habitServiceProvider);
    final name = _nameController.text.trim();
    try {
      final original = _original;
      if (original == null) {
        await service.createHabit(
          name: name,
          emoji: _emoji,
          colorValue: _colorValue,
          schedule: schedule,
          reminderTime: _reminder,
          startDate: _startDate,
        );
      } else {
        await service.updateHabit(
          original.copyWith(
            name: name,
            emoji: _emoji,
            colorValue: _colorValue,
            schedule: schedule,
            startDate: _startDate,
            reminderTime: _reminder,
            clearReminderTime: _reminder == null,
          ),
        );
      }
      if (!mounted) return;
      _close();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('Could not save: $e');
    }
  }

  Future<void> _toggleArchive() async {
    final original = _original!;
    await ref
        .read(habitServiceProvider)
        .archiveHabit(original.id, archived: !original.archived);
    if (!mounted) return;
    _showSnack(
      original.archived
          ? '${original.emoji} ${original.name} is back in action!'
          : '${original.emoji} ${original.name} archived',
    );
    _close();
  }

  Future<void> _delete() async {
    final original = _original!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Text(original.emoji, style: const TextStyle(fontSize: 40)),
        title: Text('Delete “${original.name}”?'),
        content: const Text(
          'All of its check-ins and streaks will be gone for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(habitServiceProvider).deleteHabit(original.id);
    if (!mounted) return;
    // The details screen of a deleted habit is gone too: back to the list.
    final messenger = ScaffoldMessenger.maybeOf(context);
    context.go(AppRoutes.habits);
    messenger?.showSnackBar(
      SnackBar(content: Text('${original.emoji} ${original.name} deleted')),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickStartDate() async {
    final today = ref.read(todayProvider);
    final first = _startDate.isBefore(addDays(today, -365))
        ? _startDate
        : addDays(today, -365);
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: first,
      lastDate: addDays(today, 365),
    );
    if (picked != null) setState(() => _startDate = dateOnly(picked));
  }

  Future<void> _pickReminder() async {
    final initial = _reminder == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: _reminder!.hour, minute: _reminder!.minute);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(
        () =>
            _reminder = ReminderTime(hour: picked.hour, minute: picked.minute),
      );
    }
  }

  Habit get _previewHabit => Habit(
    id: _original?.id ?? 'preview',
    name: _nameController.text.trim(),
    emoji: _emoji,
    colorValue: _colorValue,
    schedule: _schedule ?? _original?.schedule ?? const DailySchedule(),
    createdAt: _original?.createdAt ?? _startDate,
    startDate: _startDate,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = widget.isEditing && _original == null;
    if (missing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit habit')),
        body: MessageView(
          key: const ValueKey('edit-habit-not-found'),
          emoji: '🕵️',
          title: 'Habit not found',
          message: 'This habit may have been deleted.',
          action: FilledButton.icon(
            onPressed: () => context.go(AppRoutes.habits),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to habits'),
          ),
        ),
      );
    }
    final original = _original;
    final accent = HabitPalette.fromValue(_colorValue);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit habit' : 'New habit'),
        actions: [
          if (original != null) ...[
            IconButton(
              tooltip: original.archived ? 'Unarchive' : 'Archive',
              onPressed: _saving ? null : _toggleArchive,
              icon: Icon(
                original.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: _saving ? null : _delete,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionLabel('Preview'),
              HabitCard(
                habit: _previewHabit,
                showCheckIn: true,
                completed: false,
              ),
              _Section(
                label: 'Name',
                child: TextFormField(
                  key: const ValueKey('habit-name'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: HabitDefaults.maxNameLength,
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Drink water, Read 10 pages',
                  ),
                  validator: _validateName,
                  textInputAction: TextInputAction.done,
                ),
              ),
              _Section(
                label: 'Icon',
                child: EmojiPicker(
                  selected: _emoji,
                  accent: accent,
                  onSelected: (e) => setState(() => _emoji = e),
                ),
              ),
              _Section(
                label: 'Colour',
                child: HabitColorPicker(
                  selectedValue: _colorValue,
                  onSelected: (v) => setState(() => _colorValue = v),
                ),
              ),
              _Section(
                label: 'Schedule',
                child: SchedulePicker(
                  initial: _schedule ?? const DailySchedule(),
                  accent: accent,
                  onChanged: (s) => setState(() => _schedule = s),
                ),
              ),
              _Section(
                label: 'Starts',
                child: _TileButton(
                  key: const ValueKey('start-date'),
                  icon: Icons.event_rounded,
                  text: _startDate == ref.watch(todayProvider)
                      ? 'Today'
                      : DateFormat.yMMMEd().format(_startDate),
                  onTap: _pickStartDate,
                ),
              ),
              _Section(
                label: 'Reminder',
                child: Row(
                  children: [
                    Expanded(
                      child: _TileButton(
                        key: const ValueKey('reminder-time'),
                        icon: _reminder == null
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active_rounded,
                        text: _reminder == null
                            ? 'No reminder'
                            : TimeOfDay(
                                hour: _reminder!.hour,
                                minute: _reminder!.minute,
                              ).format(context),
                        onTap: _pickReminder,
                      ),
                    ),
                    if (_reminder != null)
                      IconButton(
                        key: const ValueKey('clear-reminder'),
                        tooltip: 'Clear reminder',
                        onPressed: () => setState(() => _reminder = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const ValueKey('save-habit'),
            onPressed: _saving ? null : _save,
            icon: Icon(
              widget.isEditing
                  ? Icons.check_rounded
                  : Icons.auto_awesome_rounded,
            ),
            label: Text(widget.isEditing ? 'Save changes' : 'Create habit'),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;

  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ],
    );
  }
}

class _TileButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _TileButton({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.inputDecorationTheme.fillColor,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
