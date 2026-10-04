/// Fun rotating reminder texts.
library;

import '../../data/models/habit.dart';

/// Templates; `{emoji}` and `{name}` are replaced with the habit's.
const kReminderTemplates = <String>[
  '🔥 Keep your streak alive: {emoji} {name}!',
  '⚔️ A new quest awaits: {emoji} {name}',
  '🌟 Hero time! {emoji} {name} is calling',
  '🚀 Level up today with {emoji} {name}',
  '💪 You\'ve got this: {emoji} {name}',
  '🎯 Quick win ahead: {emoji} {name}',
  '🐉 Slay the day — {emoji} {name}!',
  '✨ XP is waiting: {emoji} {name}',
];

/// Body lines shown under the title, rotated with the same seed.
const kReminderBodies = <String>[
  'Tap to check in and grow your streak.',
  'Check in now and earn your XP ✨',
  'Small steps, big adventure. Check in!',
  'Your future self says thanks 🙌',
];

/// The reminder title for [habit], picked deterministically by [seed]
/// (e.g. a day number or slot index).
String reminderTitle(Habit habit, int seed) => kReminderTemplates[
        seed.abs() % kReminderTemplates.length]
    .replaceAll('{emoji}', habit.emoji)
    .replaceAll('{name}', habit.name);

/// The reminder body for [seed].
String reminderBody(int seed) =>
    kReminderBodies[seed.abs() % kReminderBodies.length];
