import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest_admin/src/dates.dart';
import 'package:habitquest_admin/src/ui/schedule_screen.dart';

import 'helpers.dart';

void main() {
  test('buildSchedule marks the days without a quote', () {
    final days = buildSchedule(DateTime(2026, 10, 20), 4, [
      quote(1, 'a', day: '2026-10-20'),
      quote(2, 'b', day: '2026-10-22'),
      quote(3, 'c', day: '2026-11-30'),
      quote(4, 'd'),
    ]);
    expect(days.map((d) => dateKey(d.date)), [
      '2026-10-20',
      '2026-10-21',
      '2026-10-22',
      '2026-10-23',
    ]);
    expect(days.map((d) => d.isGap), [false, true, false, true]);
  });

  testWidgets('the gap view flags days without a quote and fills a gap', (
    tester,
  ) async {
    // Quotes on 20 and 22 Oct only: every other day of the 8 weeks is a gap.
    final api = fakeApi();
    await pumpApp(tester, api, size: const Size(1400, 1600));
    await signIn(tester, adminEmail);
    await openTab(tester, 'Schedule');

    expect(api.quoteQueries.last.from, '2026-10-20');
    expect(api.quoteQueries.last.to, '2026-12-14'); // 8 weeks = 56 days
    expect(
      find.text('54 days without a quote in the next 8 weeks'),
      findsOneWidget,
    );
    expect(find.textContaining('fall back to cycling'), findsOneWidget);
    expect(find.text('No quote · cycles'), findsNWidgets(54));
    expect(find.text('Small steps every day.'), findsOneWidget);

    // Tap the gap on 21 Oct: the editor opens pre-scheduled for that day.
    await tester.tap(find.byKey(const ValueKey('day-2026-10-21')));
    await tester.pumpAndSettle();
    expect(find.text('New quote'), findsOneWidget);
    expect(find.text('Scheduled for Wed 21 Oct 2026'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('quote-text')),
      'Begin anywhere.',
    );
    await tester.tap(find.byKey(const ValueKey('quote-save')));
    await tester.pumpAndSettle();

    expect(api.quotes.last.day, '2026-10-21');
    expect(
      find.text('53 days without a quote in the next 8 weeks'),
      findsOneWidget,
    );
    expect(find.text('Begin anywhere.'), findsOneWidget);
  });

  testWidgets('a fully scheduled window says so', (tester) async {
    final api = fakeApi(
      quotes: [
        for (var i = 0; i < 28; i++)
          quote(
            i + 1,
            'Quote $i',
            day: dateKey(addDays(DateTime(2026, 10, 20), i)),
          ),
      ],
    );
    await pumpApp(tester, api, size: const Size(1400, 1600));
    await signIn(tester, adminEmail);
    await openTab(tester, 'Schedule');
    await tester.tap(find.text('4 weeks'));
    await tester.pumpAndSettle();
    expect(
      find.text('Every day of the next 4 weeks has a quote.'),
      findsOneWidget,
    );
    expect(find.text('No quote · cycles'), findsNothing);
  });
}
