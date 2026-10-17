import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('wrong password shows an error and stays on sign-in', (
    tester,
  ) async {
    await pumpApp(tester, fakeApi());
    await signIn(tester, adminEmail, password: 'nope');
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.text('HabitQuest Admin'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('empty fields are rejected before calling the server', (
    tester,
  ) async {
    await pumpApp(tester, fakeApi());
    await tester.tap(find.byKey(const ValueKey('sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email and password.'), findsOneWidget);
  });

  testWidgets('a non-admin sees "Not authorised" and no admin data', (
    tester,
  ) async {
    final api = fakeApi();
    await pumpApp(tester, api);
    await signIn(tester, userEmail);
    expect(find.text('Not authorised'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(api.quoteQueries, isEmpty);
    expect(api.statsCalls, isEmpty);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
  });

  testWidgets(
    'an admin (any email case) gets the console; sign-out returns to sign-in',
    (tester) async {
      await pumpApp(tester, fakeApi());
      await signIn(tester, 'FirtaCosmin@Gmail.com');
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Quotes'), findsWidgets);
      expect(find.text('Keep going.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    },
  );
}
