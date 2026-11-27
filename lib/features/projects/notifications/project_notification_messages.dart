/// Fun copy for Projects notifications, in the tone of the habit reminders
/// (`reminder_messages.dart`). Picked deterministically by a seed so a
/// rescheduled notification keeps its text.
library;

/// Time block start. `{project}`, `{block}` and `{time}` are replaced;
/// `{block}` is the block label, or the project name when it has none.
const kWorkSplitTitles = <String>[
  '⚔️ Quest time: {block}',
  '🚀 Launch window open: {block}',
  '🧭 Focus mode: {block}',
  '🐉 Time to slay some work: {block}',
];
const kWorkSplitBodies = <String>[
  '{project}: your time block starts now ({time}). Let\'s go!',
  '{time}: a {project} block begins. Small steps, big adventure ✨',
  '{project} is on ({time}). Your future self says thanks 🙌',
];

/// Deadline approaching, by days left (3, 1, 0). `{goal}`, `{project}`.
const kDeadlineTitles = <int, List<String>>{
  3: ['⏳ 3 days to go: {goal}', '🗺️ The finish line is in sight: {goal}'],
  1: ['🔥 Tomorrow is the day: {goal}', '⚡ One day left for {goal}!'],
  0: ['🏁 Deadline day: {goal}', '🏆 Today\'s the day: {goal}!'],
};
const kDeadlineBodies = <String>[
  '{project}: give it your best shot 💪',
  '{project}: mark it done when you get there for a victory lap 🎉',
  '{project}: you\'ve got this, hero!',
];

/// Plan task delivery tomorrow. `{task}`, `{goal}`, `{project}`.
const kTaskDeliveryTitles = <String>[
  '📦 Due tomorrow: {task}',
  '🏅 Quick win ahead: {task} is due tomorrow',
  '✨ XP is waiting: deliver {task} tomorrow',
];
const kTaskDeliveryBodies = <String>[
  '{goal} · {project}. Check it off when it\'s done!',
  'Part of {goal} ({project}). One task closer to victory 🏆',
];

String pick(List<String> options, int seed) =>
    options[seed.abs() % options.length];

String fill(String template, Map<String, String> values) {
  var out = template;
  values.forEach((k, v) => out = out.replaceAll('{$k}', v));
  return out;
}
