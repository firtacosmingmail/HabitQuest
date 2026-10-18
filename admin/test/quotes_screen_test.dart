import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest_admin/src/api/models.dart';

import 'helpers.dart';

void main() {
  testWidgets(
    'lists past, today, upcoming and unscheduled quotes with love counts',
    (tester) async {
      final api = fakeApi();
      await pumpApp(tester, api);
      await signIn(tester, adminEmail);

      expect(find.byKey(const ValueKey('quote-total')), findsOneWidget);
      expect(find.text('4 quotes'), findsOneWidget);
      for (final t in [
        'Well done is better than well said.',
        'Small steps every day.',
        'The best is yet to come.',
        'Keep going.',
      ]) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('Past'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(
        find.text('Unscheduled'),
        findsWidgets,
      ); // row label + filter segment
      final q3 = api.quotes[2];
      expect(
        tester.widget<Text>(find.byKey(ValueKey('loves-${q3.id}'))).data,
        '7',
      );
      expect(find.text('Anonymous'), findsNWidgets(2));
    },
  );

  testWidgets('search filters the list through the server query', (
    tester,
  ) async {
    final api = fakeApi();
    await pumpApp(tester, api);
    await signIn(tester, adminEmail);

    await tester.enterText(
      find.byKey(const ValueKey('quote-search')),
      'browning',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.quoteQueries.last.query, 'browning');
    expect(find.text('The best is yet to come.'), findsOneWidget);
    expect(find.text('Keep going.'), findsNothing);
    expect(find.text('1 quote'), findsOneWidget);
  });

  testWidgets('scheduled filter', (tester) async {
    final api = fakeApi();
    await pumpApp(tester, api);
    await signIn(tester, adminEmail);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<ScheduledFilter>),
        matching: find.text('Unscheduled'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.quoteQueries.last.scheduled, ScheduledFilter.unscheduled);
    expect(find.text('Keep going.'), findsOneWidget);
    expect(find.text('Small steps every day.'), findsNothing);
  });

  testWidgets('create a quote; a taken day is reported inline', (tester) async {
    final api = fakeApi();
    await pumpApp(tester, api);
    await signIn(tester, adminEmail);

    await tester.tap(find.byKey(const ValueKey('new-quote')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quote-save')));
    await tester.pumpAndSettle();
    expect(find.text('The quote text is required.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('quote-text')),
      '  Begin anywhere.  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('quote-author')),
      'John Cage',
    );
    await tester.tap(find.byKey(const ValueKey('quote-save')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Begin anywhere.'), findsOneWidget);
    expect(find.text('John Cage'), findsOneWidget);
    expect(api.quotes.last.text, 'Begin anywhere.');
    expect(api.quotes.last.day, isNull);
  });

  testWidgets("edit a quote's text, then unschedule it in the editor", (
    tester,
  ) async {
    final api = fakeApi();
    await pumpApp(tester, api);
    await signIn(tester, adminEmail);

    await tester.tap(find.text('The best is yet to come.'));
    await tester.pumpAndSettle();
    expect(find.text('Edit quote'), findsOneWidget);
    expect(find.text('Scheduled for Thu 22 Oct 2026'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('quote-text')),
      'The best is yet to be.',
    );
    await tester.tap(find.byKey(const ValueKey('quote-save')));
    await tester.pumpAndSettle();
    expect(find.text('The best is yet to be.'), findsOneWidget);
    expect(api.quotes[2].day, '2026-10-22');
    expect(api.quotes[2].loves, 7);

    await tester.tap(find.text('The best is yet to be.'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quote-clear-day')));
    await tester.pumpAndSettle();
    expect(find.text('Not scheduled'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-save')));
    await tester.pumpAndSettle();
    expect(api.quotes[2].day, isNull);
  });

  testWidgets('day_taken from the server is shown in the editor', (
    tester,
  ) async {
    final api = fakeApi();
    await pumpApp(tester, api);
    await signIn(tester, adminEmail);
    await tester.tap(find.text('Well done is better than well said.'));
    await tester.pumpAndSettle();
    // Meanwhile another admin schedules a different quote on the same day.
    api.quotes[2] = api.quotes[2].copyWith(day: '2026-10-18');
    await tester.tap(find.byKey(const ValueKey('quote-save')));
    await tester.pumpAndSettle();
    expect(
      find.text('Another quote is already scheduled on 2026-10-18.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('unschedule and delete from the list', (tester) async {
    final api = fakeApi();
    await pumpApp(tester, api);
    await signIn(tester, adminEmail);
    final today = api.quotes[1];
    final past = api.quotes[0];

    await tester.tap(find.byKey(ValueKey('unschedule-${today.id}')));
    await tester.pumpAndSettle();
    expect(api.quotes[1].day, isNull);
    expect(
      find.text('Unscheduled: 2026-10-20 now falls back to cycling'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ValueKey('delete-${past.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this quote?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();
    expect(api.quotes.any((q) => q.id == past.id), isFalse);
    expect(find.text('Well done is better than well said.'), findsNothing);
    expect(find.text('3 quotes'), findsOneWidget);
  });
}
