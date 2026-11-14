/// Fun copy for Projects notifications, in the tone of the habit reminders
/// (`reminder_messages.dart`). Picked deterministically by a seed so a
/// rescheduled notification keeps its text.
library;

/// Work split start. `{project}`, `{target}` and `{time}` are replaced.
const kWorkSplitTitles = <String>[
  '⚔️ Quest time: {project}',
  '🚀 Launch window open: {project}',
  '🎯 Focus mode: {project}',
  '🐉 Time to slay some work: {project}',
];
const kWorkSplitBodies = <String>[
  'Your {target} session starts now ({time}). Let\'s go!',
  '{time}: a {target} block begins. Small steps, big adventure ✨',
  'The {target} session is on ({time}). Your future self says thanks 🙌',
];

/// Deadline approaching, by days left (3, 1, 0). `{target}`, `{project}`.
const kDeadlineTitles = <int, List<String>>{
  3: [
    '⏳ 3 days to go: {target}',
    '🗺️ The finish line is in sight: {target}',
  ],
  1: [
    '🔥 Tomorrow is the day: {target}',
    '⚡ One day left for {target}!',
  ],
  0: [
    '🏁 Deadline day: {target}',
    '🏆 Today\'s the day: {target}!',
  ],
};
const kDeadlineBodies = <String>[
  '{project}: give it your best shot 💪',
  '{project}: mark it done when you get there for a victory lap 🎉',
  '{project}: you\'ve got this, hero!',
];

/// Plan task delivery tomorrow. `{task}`, `{target}`, `{project}`.
const kTaskDeliveryTitles = <String>[
  '📦 Due tomorrow: {task}',
  '🎯 Quick win ahead: {task} is due tomorrow',
  '✨ XP is waiting: deliver {task} tomorrow',
];
const kTaskDeliveryBodies = <String>[
  '{target} · {project}. Check it off when it\'s done!',
  'Part of {target} ({project}). One task closer to victory 🏆',
];

String pick(List<String> options, int seed) =>
    options[seed.abs() % options.length];

String fill(String template, Map<String, String> values) {
  var out = template;
  values.forEach((k, v) => out = out.replaceAll('{$k}', v));
  return out;
}
