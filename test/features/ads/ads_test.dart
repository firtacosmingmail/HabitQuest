import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/config/env.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/features/ads/ad_config.dart';
import 'package:habit_quest/features/ads/ad_placement.dart';
import 'package:habit_quest/features/ads/ad_service.dart';
import 'package:habit_quest/features/ads/ad_slot.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/login_screen.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/habit_details/widgets/habit_month_calendar.dart';
import 'package:habit_quest/features/habits/widgets/habit_card.dart';

import '../../helpers/fake_ad_service.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// Monday 2026-01-05, 09:00.
DateTime clock() => DateTime(2026, 1, 5, 9);

final adFinder = find.byKey(const ValueKey('fake-ad-habitsList'));

/// The habits list from top to bottom as "C" (habit card) and "A" (ad).
String listSequence(WidgetTester tester) {
  final items = <(double, String)>[
    for (final e in find.byType(HabitCard).evaluate())
      (tester.getTopLeft(find.byWidget(e.widget)).dy, 'C'),
    for (final e in adFinder.evaluate())
      (tester.getTopLeft(find.byWidget(e.widget)).dy, 'A'),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return items.map((i) => i.$2).join();
}

Future<void> pumpHabits(WidgetTester tester, int daily, {int other = 0}) async {
  tester.view.physicalSize = const Size(420, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = InMemoryHabitRepository(
    habits: [
      for (var i = 0; i < daily; i++) habit(id: 'd$i', name: 'Daily $i'),
      // Tuesdays only: listed under "Other habits" on Monday.
      for (var i = 0; i < other; i++)
        habit(id: 'o$i', name: 'Other $i', schedule: WeekdaysSchedule({2})),
    ],
  );
  await pumpHabitQuestApp(
    tester,
    repository: repo,
    clock: clock,
    overrides: [fakeAdsOverride()],
  );
}

void main() {
  group('habitsListAdAfter', () {
    List<int> positions(int total) => [
      for (var p = 1; p <= total; p++)
        if (habitsListAdAfter(p, total)) p,
    ];

    test('after card 3, then every 6 cards', () {
      expect(positions(3), [3]);
      expect(positions(8), [3]);
      expect(positions(9), [3, 9]);
      expect(positions(20), [3, 9, 15]);
    });

    test('fewer than 3 cards: one at the end; none when empty', () {
      expect(positions(0), isEmpty);
      expect(positions(1), [1]);
      expect(positions(2), [2]);
    });
  });

  group('AdConfig', () {
    test('prod (release) uses the real app and banner unit IDs', () {
      for (final c in [
        AdConfig.resolve(isRelease: true),
        AdConfig.resolve(isRelease: false, envDefine: 'prod'),
      ]) {
        expect(c.enabled, isTrue);
        expect(c.ids.iosAppId, 'ca-app-pub-5156448354942178~4999843447');
        expect(c.ids.androidAppId, 'ca-app-pub-5156448354942178~1318609576');
        expect(
          c.unitId(AdPlacement.habitsList, ios: true),
          'ca-app-pub-5156448354942178/9628344434',
        );
        expect(
          c.unitId(AdPlacement.habitDetails, ios: true),
          'ca-app-pub-5156448354942178/4842921616',
        );
        expect(
          c.unitId(AdPlacement.habitsList, ios: false),
          'ca-app-pub-5156448354942178/3303618395',
        );
        expect(
          c.unitId(AdPlacement.habitDetails, ios: false),
          'ca-app-pub-5156448354942178/3338268258',
        );
      }
    });

    test('dev (debug) uses Google test banner units with the real app IDs', () {
      for (final c in [
        AdConfig.resolve(isRelease: false),
        AdConfig.resolve(isRelease: true, envDefine: 'dev'),
      ]) {
        expect(c.ids.iosAppId, 'ca-app-pub-5156448354942178~4999843447');
        expect(c.ids.androidAppId, 'ca-app-pub-5156448354942178~1318609576');
        for (final p in AdPlacement.values) {
          expect(
            c.unitId(p, ios: true),
            'ca-app-pub-3940256099942544/2934735716',
          );
          expect(
            c.unitId(p, ios: false),
            'ca-app-pub-3940256099942544/6300978111',
          );
        }
      }
    });

    test('dart-define overrides also apply in prod', () {
      final c = AdConfig.resolve(
        isRelease: true,
        iosHabitDetails: 'ca-app-pub-2/2',
      );
      expect(c.unitId(AdPlacement.habitDetails, ios: true), 'ca-app-pub-2/2');
      expect(
        c.unitId(AdPlacement.habitsList, ios: true),
        admobProdIds.iosHabitsListUnitId,
      );
    });

    test(
      'dart-define overrides replace single unit IDs; ADS_ENABLED=false',
      () {
        final c = AdConfig.resolve(
          isRelease: false,
          enabledDefine: 'false',
          androidHabitsList: ' ca-app-pub-1/1 ',
        );
        expect(c.enabled, isFalse);
        expect(c.unitId(AdPlacement.habitsList, ios: false), 'ca-app-pub-1/1');
        expect(
          c.unitId(AdPlacement.habitsList, ios: true),
          admobTestIds.iosHabitsListUnitId,
        );
      },
    );
  });

  group('habits list placement (fake ads)', () {
    testWidgets('after the first 3 cards, then every 6', (tester) async {
      await pumpHabits(tester, 6, other: 4);
      expect(find.byType(HabitCard), findsNWidgets(10));
      // Cards 1-6 under Today, 7-10 under Other habits: ads after 3 and 9.
      expect(listSequence(tester), 'CCCACCCCCCAC');
      // Ads sit between cards, never inside one (so never between a card
      // and its check-in button).
      expect(
        find.descendant(of: find.byType(HabitCard), matching: adFinder),
        findsNothing,
      );
      expect(find.text('Ad'), findsNWidgets(2));
    });

    testWidgets('exactly 3 cards: one ad after the third', (tester) async {
      await pumpHabits(tester, 3);
      expect(listSequence(tester), 'CCCA');
    });

    testWidgets('fewer than 3 cards: one ad at the end', (tester) async {
      await pumpHabits(tester, 2);
      expect(listSequence(tester), 'CCA');
    });

    testWidgets('empty list: no ads', (tester) async {
      await pumpHabits(tester, 0);
      expect(find.text('Your quest begins here'), findsOneWidget);
      expect(adFinder, findsNothing);
      expect(find.byType(AdSlot), findsNothing);
    });

    testWidgets('the ad frame is narrower than the habit cards', (
      tester,
    ) async {
      await pumpHabits(tester, 3);
      // The visible card surface vs the visible ad box.
      final card = tester.getRect(
        find
            .descendant(
              of: find.byType(HabitCard).first,
              matching: find.byType(Material),
            )
            .first,
      );
      final frame = tester.getRect(
        find
            .descendant(
              of: find.byType(AdFrame),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(frame.width, lessThan(card.width * 0.9));
      expect(frame.center.dx, closeTo(card.center.dx, 1));
    });
  });

  testWidgets('habit details: one ad under the monthly calendar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHabitQuestApp(
      tester,
      repository: InMemoryHabitRepository(habits: [habit()]),
      clock: clock,
      initialLocation: '/habits/h1',
      overrides: [fakeAdsOverride()],
    );
    final ad = find.byKey(const ValueKey('fake-ad-habitDetails'));
    expect(ad, findsOneWidget);
    expect(
      tester.getTopLeft(ad).dy,
      greaterThan(tester.getBottomLeft(find.byType(HabitMonthCalendar)).dy),
    );
    expect(
      tester.getTopLeft(ad).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('habit-edit-button'))).dy,
      ),
    );
  });

  testWidgets('no ads on the login screen', (tester) async {
    await pumpHabitQuestApp(
      tester,
      signedIn: false,
      overrides: [
        fakeAdsOverride(),
        backendConfigOverride,
        authApiProvider.overrideWithValue(FakeAuthApi()),
        sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        authControllerProvider.overrideWith(
          () => AuthController(proactiveRefresh: false),
        ),
      ],
    );
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(AdSlot), findsNothing);
    expect(find.byType(AdFrame), findsNothing);
  });

  testWidgets('the no-op service renders nothing', (tester) async {
    await tester.pumpWidget(
      wrapForTest(
        const Column(
          children: [
            AdSlot(key: ValueKey('slot'), placement: AdPlacement.habitsList),
          ],
        ),
        overrides: [adServiceProvider.overrideWithValue(const NoopAdService())],
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('slot'))), Size.zero);
    expect(find.byType(AdFrame), findsNothing);
    expect(find.text('Ad'), findsNothing);
  });

  testWidgets('tests and desktop hosts get the no-op by default', (
    tester,
  ) async {
    final container = await pumpHabitQuestApp(tester);
    expect(container.read(adServiceProvider), isA<NoopAdService>());
  });
}
