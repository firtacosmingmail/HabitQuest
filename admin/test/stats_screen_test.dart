import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest_admin/src/ui/charts.dart';

import 'helpers.dart';

void main() {
  Future<void> openStats(WidgetTester tester, dynamic api) async {
    await pumpApp(tester, api, size: const Size(1400, 5000));
    await signIn(tester, adminEmail);
    await openTab(tester, 'Stats');
  }

  testWidgets('dashboard shows KPIs, every chart and the widget-usage note', (
    tester,
  ) async {
    final api = fakeApi();
    await openStats(tester, api);

    // Default range: the last 30 UTC days up to today.
    final (from, to) = api.statsCalls.single;
    expect(to, dateOnlyUtcKey(testNow));
    expect(DateTime.parse(to).difference(DateTime.parse(from)).inDays, 29);

    expect(find.text('Total users'), findsOneWidget);
    expect(find.text('1,284'), findsOneWidget);
    for (final title in [
      'Daily active users',
      'Weekly active users',
      'Completions per day',
      'New sign-ups per day',
      'New sign-ups per week',
      'Habits created per day',
      'Quote loves per day',
      'XP distribution',
      'Best streak distribution',
      'Highest level reached',
      'Most-loved quotes',
      'Widget usage',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.byType(SeriesChart), findsNWidgets(10));
    expect(
      find.text('Fall seven times, stand up eight.', findRichText: true),
      findsNothing,
    );
    expect(find.text('“Fall seven times, stand up eight.”'), findsOneWidget);
  });

  testWidgets('the range presets refetch every chart', (tester) async {
    final api = fakeApi();
    await openStats(tester, api);
    await tester.tap(find.byKey(const ValueKey('range-last7')));
    await tester.pumpAndSettle();
    final (from, to) = api.statsCalls.last;
    expect(DateTime.parse(to).difference(DateTime.parse(from)).inDays, 6);
    final chart = tester.widget<SeriesChart>(find.byType(SeriesChart).first);
    expect(chart.values.length, 7);
  });

  testWidgets('each chart has a table view with the values', (tester) async {
    final api = fakeApi();
    await openStats(tester, api);
    await tester.tap(find.byTooltip('Show table').at(7)); // XP distribution
    await tester.pumpAndSettle();
    expect(find.text('XP'), findsOneWidget);
    expect(find.text('100–499'), findsWidgets);
    expect(find.text('310'), findsWidgets);
    expect(find.byType(SeriesChart), findsNWidgets(9));
  });

  testWidgets('hovering a chart shows a tooltip with the value', (
    tester,
  ) async {
    final api = fakeApi();
    await openStats(tester, api);
    final chart = find.byType(SeriesChart).at(7); // XP distribution, 8 columns
    final box = tester.getRect(chart);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: box.centerLeft + const Offset(1, 0));
    addTearDown(gesture.removePointer);
    // Third column (100–499): plot spans 44..width-40.
    final plotW = box.width - 44 - 40;
    await gesture.moveTo(
      box.topLeft + Offset(44 + plotW * 2.5 / 8, box.height / 2),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: chart, matching: find.text('310')),
      findsOneWidget,
    );
  });

  test('number formatting and ticks', () {
    expect(groupThousands(1284), '1,284');
    expect(groupThousands(33.4), '33.4');
    expect(compactNumber(12900), '12.9K');
    expect(compactNumber(4200000), '4.2M');
    expect(niceTicks(37), [0, 10, 20, 30, 40]);
    expect(niceTicks(0), [0, 1]);
  });
}

String dateOnlyUtcKey(DateTime now) =>
    now.toUtc().toIso8601String().substring(0, 10);
