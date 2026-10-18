import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitquest_admin/src/api/fake_admin_api.dart';
import 'package:habitquest_admin/src/api/models.dart';
import 'package:habitquest_admin/src/app.dart';

/// Local "now" of every test: Tue 20 Oct 2026, noon.
final testNow = DateTime(2026, 10, 20, 12);

const adminEmail = 'firtacosmin@gmail.com';
const userEmail = 'alice@example.com';

AdminQuote quote(
  int n,
  String text, {
  String? day,
  String? author,
  int loves = 0,
}) => AdminQuote(
  id: '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  text: text,
  author: author,
  day: day,
  loves: loves,
  createdAt: '2026-10-16T12:00:0$n.000Z',
);

FakeAdminApi fakeApi({List<AdminQuote>? quotes}) => FakeAdminApi(
  passwords: {adminEmail: 'secret', userEmail: 'secret'},
  admins: {adminEmail},
  quotes:
      quotes ??
      [
        quote(
          1,
          'Well done is better than well said.',
          day: '2026-10-18',
          author: 'Benjamin Franklin',
          loves: 3,
        ),
        quote(2, 'Small steps every day.', day: '2026-10-20', loves: 1),
        quote(
          3,
          'The best is yet to come.',
          day: '2026-10-22',
          author: 'Robert Browning',
          loves: 7,
        ),
        quote(4, 'Keep going.'),
      ],
);

Future<void> pumpApp(
  WidgetTester tester,
  FakeAdminApi api, {
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AdminApp(api: api, now: () => testNow));
}

Future<void> signIn(
  WidgetTester tester,
  String email, {
  String password = 'secret',
}) async {
  await tester.enterText(find.byKey(const ValueKey('email')), email);
  await tester.enterText(find.byKey(const ValueKey('password')), password);
  await tester.tap(find.byKey(const ValueKey('sign-in')));
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}
