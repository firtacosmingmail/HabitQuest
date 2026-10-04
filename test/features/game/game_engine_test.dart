import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/habit_events.dart';
import 'package:habit_quest/domain/habit_service.dart';
import 'package:habit_quest/features/game/achievements.dart';
import 'package:habit_quest/features/game/game_engine.dart';
import 'package:habit_quest/features/game/game_events.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_state.dart';

import '../../helpers/fixtures.dart';

/// Monday.
final today = d(2026, 1, 5);
final clock = DateTime(2026, 1, 5, 10);

class Harness {
  final InMemoryHabitRepository repo;
  final HabitService service;
  final InMemoryGameRepository gameRepo;
  final GameEngine engine;
  final List<GameEvent> events = [];

  Harness._(this.repo, this.service, this.gameRepo, this.engine) {
    engine.events.listen(events.add);
  }

  factory Harness({
    List<Habit> habits = const [],
    Map<String, Iterable<DateTime>> completions = const {},
    GameState initial = GameState.empty,
  }) {
    final repo = InMemoryHabitRepository(
      habits: habits,
      completions: completions,
    );
    final service = HabitService(repo, now: () => clock);
    final gameRepo = InMemoryGameRepository(initial);
    final engine = GameEngine(
      service: service,
      repository: gameRepo,
      now: () => clock,
    )..start();
    final h = Harness._(repo, service, gameRepo, engine);
    addTearDown(engine.dispose);
    return h;
  }

  int get xp => engine.state.xp;

  Future<void> check(String id, DateTime date, [bool done = true]) async {
    await service.setCompletion(id, date, done);
    await pumpEventQueue();
  }

  Future<void> toggle(String id, DateTime date) async {
    await service.toggleCompletion(id, date);
    await pumpEventQueue();
  }

  List<T> eventsOf<T extends GameEvent>() => events.whereType<T>().toList();

  bool unlocked(String id) => engine.state.unlocked.containsKey(id);
}

/// A state with [n] fake check-ins worth [xpEach] XP each.
GameState seeded(int n, {int xpEach = 0}) => GameState(
  checkInLedger: {for (var i = 0; i < n; i++) 'seed$i|2025-01-01': xpEach},
);

void main() {
  group('check-in XP', () {
    test('first check-in: 10 + 1 streak bonus', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
      );
      await h.check('a', today);
      expect(h.xp, 11);
      final gained = h.eventsOf<XpGained>().single;
      expect(gained.amount, 11);
      expect(gained.habitId, 'a');
      expect(gained.reason, XpReason.checkIn);
      expect(gained.date, today);
    });

    test('streak bonus is +1 per streak day', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
        completions: {'a': range(d(2026, 1, 1), d(2026, 1, 4))},
      );
      await h.check('a', today); // streak 5
      expect(h.xp, 15);
    });

    test('streak bonus is capped at +10', () async {
      final h = Harness(
        habits: [
          habit(id: 'a', startDate: d(2025, 11, 1)),
          habit(id: 'b'),
        ],
        completions: {'a': range(d(2025, 11, 1), d(2026, 1, 4))},
      );
      await h.check('a', today);
      expect(h.xp, 20);
    });

    test('back-dated check-in uses the streak as of that day', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
        completions: {'a': range(d(2026, 1, 1), d(2026, 1, 2))},
      );
      await h.check('a', d(2026, 1, 3)); // streak 3 on Jan 3
      expect(h.xp, 13);
    });

    test('no streak bonus on a non-scheduled day', () async {
      final h = Harness(
        habits: [
          habit(
            id: 'a',
            schedule: WeekdaysSchedule({1}), // Mondays
            startDate: d(2025, 12, 1),
          ),
        ],
        completions: {
          'a': [d(2025, 12, 29)],
        },
      );
      await h.check('a', d(2025, 12, 30)); // Tuesday: nothing is due
      expect(h.xp, 10);
      expect(h.engine.state.perfectDays, 0);
    });

    test('un-checking reverses exactly what was granted', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
        completions: {'a': range(d(2026, 1, 1), d(2026, 1, 3))},
      );
      await h.check('a', d(2026, 1, 4)); // streak 4 -> 14
      await h.check('a', today); // streak 5 -> 15
      expect(h.xp, 29);
      // Removing Jan 4 breaks the streak, but Jan 5 keeps its 15 and only
      // the 14 granted for Jan 4 is taken back.
      await h.check('a', d(2026, 1, 4), false);
      expect(h.xp, 15);
      final lost = h.eventsOf<XpLost>().single;
      expect(lost.amount, 14);
      expect(lost.reason, XpReason.checkIn);
      expect(lost.habitId, 'a');
    });

    test(
      'un-checking a check-in that never earned XP changes nothing',
      () async {
        final h = Harness(
          habits: [habit(id: 'a')],
          completions: {
            'a': [today],
          },
        );
        await h.check('a', today, false);
        expect(h.xp, 0);
        expect(h.eventsOf<XpLost>(), isEmpty);
      },
    );

    test('a duplicate completion event never grants twice', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
      );
      await h.check('a', today);
      h.engine.handleCompletion(
        CompletionEvent(habitId: 'a', date: today, completed: true),
      );
      expect(h.xp, 11);
      expect(h.eventsOf<XpGained>(), hasLength(1));
    });
  });

  group('Perfect Day', () {
    test(
      'granted when every due habit is done, reversed on un-check',
      () async {
        final h = Harness(
          habits: [
            habit(id: 'a'),
            habit(id: 'b'),
          ],
        );
        await h.check('a', today);
        expect(h.engine.state.perfectDays, 0);
        await h.check('b', today);
        expect(h.xp, 11 + 11 + 25);
        expect(h.engine.state.perfectDays, 1);
        final bonus = h
            .eventsOf<XpGained>()
            .where((e) => e.reason == XpReason.perfectDay)
            .single;
        expect(bonus.amount, 25);
        expect(bonus.habitId, isNull);
        expect(bonus.date, today);

        await h.check('b', today, false);
        expect(h.xp, 11);
        expect(h.engine.state.perfectDays, 0);
        final lost = h.eventsOf<XpLost>().map((e) => (e.reason, e.amount));
        expect(
          lost,
          containsAll([(XpReason.checkIn, 11), (XpReason.perfectDay, 25)]),
        );
      },
    );

    test('unrelated habits not due that day do not block it', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b', schedule: WeekdaysSchedule({2})), // Tuesdays
          habit(id: 'z', archived: true),
        ],
      );
      await h.check('a', today);
      expect(h.xp, 11 + 25);
    });

    test('back-filled past days can become perfect', () async {
      final h = Harness(habits: [habit(id: 'a')]);
      await h.check('a', d(2026, 1, 2));
      expect(h.engine.state.perfectDayLedger.keys, ['2026-01-02']);
    });

    test(
      'times-per-week check-in re-evaluates later days of the week',
      () async {
        final week = d(2026, 1, 12); // Monday; today is Wednesday 14th
        final repo = InMemoryHabitRepository(
          habits: [
            habit(id: 'w', schedule: TimesPerWeekSchedule(1)),
            habit(id: 'd', schedule: WeekdaysSchedule({2})), // Tuesdays
          ],
          completions: {
            'd': [d(2026, 1, 13)],
          },
        );
        final service = HabitService(repo, now: () => DateTime(2026, 1, 14));
        final engine = GameEngine(
          service: service,
          repository: InMemoryGameRepository(),
          now: () => DateTime(2026, 1, 14),
        )..start();
        addTearDown(engine.dispose);
        // Tue 13th: both 'w' (target not met yet) and 'd' are due; 'w' undone.
        // Checking 'w' on Monday makes 'w' no longer due on Tuesday, so
        // Tuesday becomes perfect too.
        await service.setCompletion('w', week, true);
        await pumpEventQueue();
        expect(engine.state.perfectDayLedger.keys.toSet(), {
          '2026-01-12',
          '2026-01-13',
        });
      },
    );

    test('deleting a habit removes its XP and perfect days it made', () async {
      final h = Harness(habits: [habit(id: 'a')]);
      await h.check('a', d(2026, 1, 4));
      await h.check('a', today);
      expect(h.xp, 11 + 25 + 12 + 25);
      await h.service.deleteHabit('a');
      await pumpEventQueue();
      expect(h.xp, 0);
      expect(h.engine.state.totalCheckIns, 0);
      expect(h.engine.state.perfectDays, 0);
      final deleted = h
          .eventsOf<XpLost>()
          .where((e) => e.reason == XpReason.habitDeleted)
          .single;
      expect(deleted.amount, 23);
      // Achievements stay.
      expect(h.unlocked(AchievementIds.firstCheckIn), isTrue);
      expect(h.unlocked(AchievementIds.firstPerfectDay), isTrue);
    });

    test('creating or archiving habits never changes XP', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
      );
      await h.check('a', today);
      await h.check('b', today);
      final xp = h.xp;
      await h.service.createHabit(name: 'New', emoji: '⭐', colorValue: 0);
      await h.service.archiveHabit('b');
      await pumpEventQueue();
      expect(h.xp, xp);
    });
  });

  group('toggle exploit', () {
    test('toggling on/off repeatedly nets 0 and no duplicate bonus', () async {
      final h = Harness(habits: [habit(id: 'a')]);
      for (var i = 0; i < 24; i++) {
        await h.toggle('a', today);
        expect(h.xp, i.isEven ? 11 + 25 : 0, reason: 'toggle $i');
      }
      expect(h.engine.state.checkInLedger, isEmpty);
      expect(h.engine.state.perfectDayLedger, isEmpty);
      expect(h.engine.state.totalCheckIns, 0);
      // Each achievement is announced once.
      expect(h.eventsOf<AchievementUnlocked>().map((e) => e.achievement.id), [
        AchievementIds.firstCheckIn,
        AchievementIds.firstPerfectDay,
      ]);
      // Achievements stay unlocked once earned.
      expect(h.unlocked(AchievementIds.firstCheckIn), isTrue);
      expect(h.unlocked(AchievementIds.firstPerfectDay), isTrue);
    });

    test('rapid toggles without waiting for events still net 0', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
      );
      for (var i = 0; i < 10; i++) {
        await h.service.toggleCompletion('a', today);
        await h.service.toggleCompletion('b', today);
      }
      await pumpEventQueue();
      expect(h.xp, 0);
      await h.service.toggleCompletion('a', today);
      await pumpEventQueue();
      expect(h.xp, 11);
    });

    test('toggling cannot farm check-in achievements', () async {
      final h = Harness(habits: [habit(id: 'a')]);
      for (var i = 0; i < 30; i++) {
        await h.toggle('a', today);
      }
      expect(h.unlocked(AchievementIds.checkIns10), isFalse);
    });

    test('re-reaching a level does not celebrate again', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
        initial: seeded(1, xpEach: 95),
      );
      await h.check('a', today);
      expect(h.engine.profile.level, 2);
      await h.check('a', today, false);
      expect(h.engine.profile.level, 1);
      await h.check('a', today);
      expect(h.engine.profile.level, 2);
      final ups = h.eventsOf<LevelUp>();
      expect(ups, hasLength(1));
      expect(ups.single.newLevel, 2);
      expect(ups.single.title, 'Sprout');
    });
  });

  group('levels', () {
    test('LevelUp fires with the new title, after the XP event', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
        initial: GameState(
          checkInLedger: {'seed|2025-01-01': 295},
          maxLevelReached: 2,
        ),
      );
      expect(h.engine.profile.level, 2);
      await h.check('a', today);
      expect(h.engine.profile.level, 3);
      expect(h.engine.profile.title, 'Seeker');
      final types = h.events.map((e) => e.runtimeType).toList();
      expect(types.indexOf(XpGained), lessThan(types.indexOf(LevelUp)));
      final up = h.eventsOf<LevelUp>().single;
      expect((up.newLevel, up.title), (3, 'Seeker'));
    });
  });

  group('achievements', () {
    test('first habit', () async {
      final h = Harness();
      expect(h.unlocked(AchievementIds.firstHabit), isFalse);
      await h.service.createHabit(name: 'Read', emoji: '📚', colorValue: 0);
      await pumpEventQueue();
      expect(h.unlocked(AchievementIds.firstHabit), isTrue);
      expect(h.engine.state.unlocked[AchievementIds.firstHabit], clock);
      expect(
        h.eventsOf<AchievementUnlocked>().single.achievement.id,
        AchievementIds.firstHabit,
      );
    });

    test('first habit is caught up at start for existing habits', () {
      final h = Harness(habits: [habit(id: 'a')]);
      expect(h.unlocked(AchievementIds.firstHabit), isTrue);
    });

    test('5 active habits (archived do not count)', () async {
      final h = Harness(
        habits: [
          for (var i = 0; i < 4; i++) habit(id: 'h$i'),
          habit(id: 'z', archived: true),
        ],
      );
      expect(h.unlocked(AchievementIds.fiveActiveHabits), isFalse);
      await h.service.archiveHabit('z', archived: false);
      await pumpEventQueue();
      expect(h.unlocked(AchievementIds.fiveActiveHabits), isTrue);
      // Stays unlocked after archiving again.
      await h.service.archiveHabit('z');
      await pumpEventQueue();
      expect(h.unlocked(AchievementIds.fiveActiveHabits), isTrue);
    });

    test('5 active habits by creating them', () async {
      final h = Harness();
      for (var i = 0; i < 5; i++) {
        await h.service.createHabit(name: 'H$i', emoji: '⭐', colorValue: 0);
      }
      await pumpEventQueue();
      expect(h.unlocked(AchievementIds.fiveActiveHabits), isTrue);
    });

    test('first check-in', () async {
      final h = Harness(habits: [habit(id: 'a')]);
      expect(h.unlocked(AchievementIds.firstCheckIn), isFalse);
      await h.check('a', today);
      expect(h.unlocked(AchievementIds.firstCheckIn), isTrue);
    });

    test('first Perfect Day', () async {
      final h = Harness(
        habits: [
          habit(id: 'a'),
          habit(id: 'b'),
        ],
      );
      await h.check('a', today);
      expect(h.unlocked(AchievementIds.firstPerfectDay), isFalse);
      await h.check('b', today);
      expect(h.unlocked(AchievementIds.firstPerfectDay), isTrue);
    });

    for (final (id, n) in [
      (AchievementIds.checkIns10, 10),
      (AchievementIds.checkIns50, 50),
      (AchievementIds.checkIns100, 100),
      (AchievementIds.checkIns500, 500),
    ]) {
      test('$n total check-ins', () async {
        final h = Harness(
          habits: [habit(id: 'a')],
          initial: seeded(n - 1),
        );
        expect(h.unlocked(id), isFalse);
        await h.check('a', today);
        expect(h.engine.state.totalCheckIns, n);
        expect(h.unlocked(id), isTrue);
      });
    }

    for (final (id, n) in [
      (AchievementIds.streak3, 3),
      (AchievementIds.streak7, 7),
      (AchievementIds.streak30, 30),
      (AchievementIds.streak100, 100),
    ]) {
      test('streak of $n', () async {
        final start = DateTime(2026, 1, 5 - (n - 1));
        final h = Harness(
          habits: [habit(id: 'a', startDate: start)],
          completions: {'a': range(start, d(2026, 1, 4))},
        );
        expect(h.engine.state.bestStreakEver, n - 1);
        expect(h.unlocked(id), isFalse);
        await h.check('a', today);
        expect(h.engine.state.bestStreakEver, n);
        expect(h.unlocked(id), isTrue);
      });
    }

    test('streak achievements also count weekly streaks', () async {
      final h = Harness(
        habits: [
          habit(
            id: 'w',
            schedule: TimesPerWeekSchedule(1),
            startDate: d(2025, 12, 22),
          ),
        ],
        completions: {
          'w': [d(2025, 12, 22), d(2025, 12, 29)],
        },
      );
      await h.check('w', today);
      expect(h.engine.state.bestStreakEver, 3);
      expect(h.unlocked(AchievementIds.streak3), isTrue);
    });

    test('each achievement is announced once and survives un-checks', () async {
      final h = Harness(
        habits: [habit(id: 'a', startDate: d(2026, 1, 3))],
        completions: {
          'a': [d(2026, 1, 3), d(2026, 1, 4)],
        },
      );
      await h.check('a', today);
      await h.check('a', today, false);
      await h.check('a', today);
      final ids = h.eventsOf<AchievementUnlocked>().map(
        (e) => e.achievement.id,
      );
      expect(ids.toSet().length, ids.length);
      expect(ids, contains(AchievementIds.streak3));
      expect(h.unlocked(AchievementIds.streak3), isTrue);
    });
  });

  group('lifecycle', () {
    test('state is persisted through the repository', () async {
      final h = Harness(habits: [habit(id: 'a')]);
      await h.check('a', today);
      await h.engine.flush();
      expect(h.gameRepo.load(), h.engine.state);
      expect(h.gameRepo.load().xp, 36);
    });

    test(
      'a restarted engine reverses check-ins from the persisted ledger',
      () async {
        final repo = InMemoryHabitRepository(habits: [habit(id: 'a')]);
        final service = HabitService(repo, now: () => clock);
        final gameRepo = InMemoryGameRepository();
        final first = GameEngine(service: service, repository: gameRepo)
          ..start();
        await service.setCompletion('a', today, true);
        await pumpEventQueue();
        await first.dispose();

        final second = GameEngine(service: service, repository: gameRepo)
          ..start();
        addTearDown(second.dispose);
        expect(second.state.xp, 36);
        await service.setCompletion('a', today, false);
        await pumpEventQueue();
        expect(second.state.xp, 0);
      },
    );

    test(
      'stateChanges emits after each change; disposed engine ignores events',
      () async {
        final h = Harness(
          habits: [
            habit(id: 'a'),
            habit(id: 'b'),
          ],
        );
        final states = <GameState>[];
        h.engine.stateChanges.listen(states.add);
        await h.check('a', today);
        expect(states.last.xp, 11);
        await h.engine.dispose();
        await h.service.setCompletion('b', today, true);
        await pumpEventQueue();
        expect(h.engine.state.xp, 11);
      },
    );
  });
}
