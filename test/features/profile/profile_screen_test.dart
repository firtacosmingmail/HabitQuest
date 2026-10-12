import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/theme/app_theme.dart';
import 'package:habit_quest/data/remote/account_api.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_account_api.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/data/sync/change_recorder.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/data/sync/sync_meta.dart';
import 'package:habit_quest/data/sync/sync_queue.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/login_screen.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/game/game_providers.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:habit_quest/features/notifications/notifications_providers.dart';
import 'package:habit_quest/features/notifications/reminder_request.dart';
import 'package:habit_quest/features/notifications/scheduler/fake_notification_scheduler.dart';
import 'package:habit_quest/features/profile/profile_controller.dart';
import 'package:habit_quest/features/profile/profile_screen.dart';
import 'package:habit_quest/features/quest/quest_screen.dart';
import 'package:habit_quest/features/sync/connectivity.dart';
import 'package:habit_quest/features/sync/sync_providers.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

class _Harness {
  final account = FakeAccountApi(password: 'secret1');
  final auth = FakeAuthApi()..addUser('hero@example.com', 'secret1');
  final store = InMemorySessionStore(testSession);
  final connectivity = FakeConnectivityMonitor();
  final scheduler = FakeNotificationScheduler();
  final queue = SyncQueue(MemoryStringStore());
  final meta = SyncMeta(MemoryStringStore());
  final repository = InMemoryHabitRepository();
  final game = InMemoryGameRepository(
    GameState(checkInLedger: const {'h1|2026-01-01': 10}, maxLevelReached: 1),
  );
  late ProviderContainer container;
}

DateTime clock() => DateTime(2026, 10, 12, 9);

void main() {
  Future<_Harness> pumpProfile(
    WidgetTester tester, {
    _Harness? harness,
    String initialLocation = '/profile',
    ThemeMode? themeMode,
  }) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = harness ?? _Harness();
    h.container = await pumpHabitQuestApp(
      tester,
      clock: clock,
      repository: h.repository,
      initialLocation: initialLocation,
      signedIn: false,
      overrides: [
        authApiProvider.overrideWithValue(h.auth),
        sessionStoreProvider.overrideWithValue(h.store),
        authControllerProvider.overrideWith(
          () => AuthController(
            preloadedSession: testSession,
            proactiveRefresh: false,
          ),
        ),
        accountApiProvider.overrideWithValue(h.account),
        connectivityMonitorProvider.overrideWithValue(h.connectivity),
        notificationSchedulerProvider.overrideWithValue(h.scheduler),
        syncQueueProvider.overrideWithValue(h.queue),
        syncMetaProvider.overrideWithValue(h.meta),
        gameRepositoryProvider.overrideWithValue(h.game),
      ],
    );
    return h;
  }

  Future<void> openDialog(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  group('display', () {
    testWidgets('shows initials, name, email, member since and method', (
      tester,
    ) async {
      final h = await pumpProfile(tester);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(h.account.calls, ['getProfile']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-avatar')),
          matching: find.text('QH'),
        ),
        findsOneWidget,
      );
      expect(find.text('Quest Hero'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-email')), findsOneWidget);
      expect(find.text('hero@example.com'), findsOneWidget);
      expect(find.text('Member since'), findsOneWidget);
      expect(find.text('March 2026'), findsOneWidget);
      expect(find.text('Email & password'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('change-password-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('danger-zone')), findsOneWidget);
    });

    testWidgets('social accounts: no Change password, provider shown', (
      tester,
    ) async {
      final h = _Harness();
      h.account.profile = AccountProfile(
        id: 'test-user',
        email: 'hero@example.com',
        createdAt: DateTime.utc(2026, 1, 2),
        providers: const ['google'],
        hasPassword: false,
      );
      await pumpProfile(tester, harness: h);
      expect(find.text('Google'), findsOneWidget);
      expect(find.text('Nameless hero'), findsOneWidget);
      expect(find.text('H'), findsWidgets);
      expect(
        find.byKey(const ValueKey('change-password-button')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('logout-button')), findsOneWidget);
    });

    testWidgets('offline load: friendly error with retry, logout still there', (
      tester,
    ) async {
      final h = _Harness();
      h.account.offline = true;
      await pumpProfile(tester, harness: h);
      expect(find.byKey(const ValueKey('profile-load-error')), findsOneWidget);
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.byKey(const ValueKey('logout-button')), findsOneWidget);
      h.account.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Quest Hero'), findsOneWidget);
    });

    testWidgets('renders in dark mode too', (tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrapForTest(
          Theme(data: AppTheme.dark, child: const ProfileScreen()),
          overrides: [
            ...signedInOverrides(),
            accountApiProvider.overrideWithValue(FakeAccountApi()),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quest Hero'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Quest header avatar opens /profile', (tester) async {
      await pumpProfile(tester, initialLocation: '/quest');
      expect(find.byType(QuestScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('logout-button')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  group('edit name', () {
    testWidgets('saves the trimmed name', (tester) async {
      final h = await pumpProfile(tester);
      await tester.tap(find.byKey(const ValueKey('edit-display-name')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('display-name-field')),
        '  Brave Sprout  ',
      );
      await tester.tap(find.byKey(const ValueKey('save-display-name')));
      await tester.pumpAndSettle();
      expect(h.account.profile.displayName, 'Brave Sprout');
      expect(find.text('Brave Sprout'), findsOneWidget);
      expect(find.text('BS'), findsOneWidget);
      expect(find.text('Name updated! ✨'), findsOneWidget);
    });

    testWidgets('validates empty and too long names; cancel keeps the old', (
      tester,
    ) async {
      final h = await pumpProfile(tester);
      await tester.tap(find.byKey(const ValueKey('edit-display-name')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('display-name-field'));
      await tester.enterText(field, '   ');
      await tester.tap(find.byKey(const ValueKey('save-display-name')));
      await tester.pumpAndSettle();
      expect(find.text('Give your hero a name'), findsOneWidget);
      expect(h.account.calls, isNot(contains('updateDisplayName')));

      await tester.tap(find.byKey(const ValueKey('cancel-display-name')));
      await tester.pumpAndSettle();
      expect(find.text('Quest Hero'), findsOneWidget);
    });

    testWidgets('shows server errors inline', (tester) async {
      final h = await pumpProfile(tester);
      h.account.failNextWith = const ApiException(
        code: ApiException.networkError,
        message: 'down',
      );
      await tester.tap(find.byKey(const ValueKey('edit-display-name')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('display-name-field')),
        'New',
      );
      await tester.tap(find.byKey(const ValueKey('save-display-name')));
      await tester.pumpAndSettle();
      expect(
        find.text("You're offline. Try again when you're back online."),
        findsOneWidget,
      );
      expect(h.account.profile.displayName, 'Quest Hero');
    });
  });

  group('change password', () {
    Future<void> fill(
      WidgetTester tester, {
      required String current,
      required String next,
      required String confirm,
    }) async {
      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        current,
      );
      await tester.enterText(find.byKey(const ValueKey('new-password')), next);
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        confirm,
      );
      await tester.tap(find.byKey(const ValueKey('submit-change-password')));
      await tester.pumpAndSettle();
    }

    testWidgets('client-side validation', (tester) async {
      final h = await pumpProfile(tester);
      await openDialog(tester, 'change-password-button');
      expect(
        find.byKey(const ValueKey('change-password-dialog')),
        findsOneWidget,
      );

      await fill(tester, current: '', next: '', confirm: '');
      expect(find.text('Enter your current password'), findsOneWidget);
      expect(find.text('Enter a new password'), findsOneWidget);

      await fill(tester, current: 'secret1', next: 'abc', confirm: 'abc');
      expect(find.text('Use at least 6 characters'), findsOneWidget);

      await fill(tester, current: 'secret1', next: 'secret1', confirm: 'x');
      expect(
        find.text('Pick something different from your current one'),
        findsOneWidget,
      );
      expect(find.text("Passwords don't match"), findsOneWidget);
      expect(h.account.calls, isNot(contains('changePassword')));
    });

    testWidgets('wrong current password is shown on that field', (
      tester,
    ) async {
      final h = await pumpProfile(tester);
      await openDialog(tester, 'change-password-button');
      await fill(
        tester,
        current: 'nope',
        next: 'brandnew',
        confirm: 'brandnew',
      );
      expect(find.text("That's not your current password"), findsOneWidget);
      expect(h.account.password, 'secret1');
      expect(
        find.byKey(const ValueKey('change-password-dialog')),
        findsOneWidget,
      );
    });

    testWidgets('success: changed, signed in again with the new password', (
      tester,
    ) async {
      final h = _Harness();
      // The real server shares the password between both functions.
      h.auth.addUser('hero@example.com', 'brandnew');
      await pumpProfile(tester, harness: h);
      await openDialog(tester, 'change-password-button');
      await fill(
        tester,
        current: 'secret1',
        next: 'brandnew',
        confirm: 'brandnew',
      );
      expect(h.account.password, 'brandnew');
      expect(
        find.byKey(const ValueKey('change-password-dialog')),
        findsNothing,
      );
      expect(find.text('Password changed! 🔐'), findsOneWidget);
      // The server revoked the old session: a fresh one was obtained.
      expect(h.auth.calls, contains('login'));
      expect(h.store.session?.accessToken, isNot(testSession.accessToken));
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  group('delete account', () {
    Future<void> seedLocalData(_Harness h) async {
      await h.repository.saveHabit(habit());
      await h.repository.setCompletion('h1', d(2026, 10, 11), true);
      await h.queue.recordChange(SyncEntityType.habit, 'h1');
      await h.meta.setOwner('test-user');
      await h.meta.setHabitsCursor('test-user', DateTime.utc(2026, 10, 1));
      await h.scheduler.schedule([
        ReminderRequest(
          id: 7,
          habitId: 'h1',
          slot: 0,
          title: 'Drink water',
          body: 'Time!',
          repeat: ReminderRepeat.daily,
          firstFire: DateTime(2026, 10, 13, 8),
        ),
      ]);
    }

    testWidgets('needs DELETE typed; cancel keeps the account', (tester) async {
      final h = await pumpProfile(tester);
      await openDialog(tester, 'delete-account-button');
      expect(
        find.byKey(const ValueKey('delete-account-dialog')),
        findsOneWidget,
      );
      FilledButton confirm() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-delete-account')),
      );
      expect(confirm().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('delete-confirm-field')),
        'delete',
      );
      await tester.pump();
      expect(confirm().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('delete-confirm-field')),
        'DELETE',
      );
      await tester.pump();
      expect(confirm().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('cancel-delete-account')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(h.account.calls, isNot(contains('deleteAccount')));
      expect(h.store.session, isNotNull);
    });

    testWidgets('deletes, wipes local data and lands on login', (tester) async {
      final h = _Harness();
      await seedLocalData(h);
      await pumpProfile(tester, harness: h);
      expect(h.repository.getHabits(), isNotEmpty);

      await openDialog(tester, 'delete-account-button');
      await tester.enterText(
        find.byKey(const ValueKey('delete-confirm-field')),
        'DELETE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-account')));
      await tester.pumpAndSettle();

      expect(h.account.deleted, isTrue);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(AuthController.accountDeletedMessage), findsOneWidget);
      expect(find.text('👋'), findsWidgets);
      expect(h.container.read(authControllerProvider), isA<SignedOut>());
      // Local data: habits, check-ins, game, queue, cursors, owner, reminders.
      expect(h.repository.getHabits(), isEmpty);
      expect(h.repository.getAllCheckIns(), isEmpty);
      expect(h.container.read(gameEngineProvider).state, GameState.empty);
      expect(h.queue.isEmpty, isTrue);
      expect(h.meta.ownerUserId, isNull);
      expect(h.meta.habitsCursor('test-user'), isNull);
      expect(h.scheduler.pending, isEmpty);
    });

    testWidgets('offline: explains it and deletes nothing', (tester) async {
      final h = _Harness();
      await seedLocalData(h);
      h.connectivity.online = false;
      await pumpProfile(tester, harness: h);
      await openDialog(tester, 'delete-account-button');
      await tester.enterText(
        find.byKey(const ValueKey('delete-confirm-field')),
        'DELETE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-account')));
      await tester.pumpAndSettle();

      expect(
        find.text('You need to be online to delete your account.'),
        findsOneWidget,
      );
      expect(h.account.calls, isNot(contains('deleteAccount')));
      expect(h.repository.getHabits(), isNotEmpty);
      expect(h.meta.ownerUserId, 'test-user');
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('a network failure mid-request shows the offline message', (
      tester,
    ) async {
      final h = _Harness();
      await seedLocalData(h);
      await pumpProfile(tester, harness: h);
      h.account.offline = true;
      await openDialog(tester, 'delete-account-button');
      await tester.enterText(
        find.byKey(const ValueKey('delete-confirm-field')),
        'DELETE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-delete-account')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('delete-account-error')),
        findsOneWidget,
      );
      expect(
        find.text('You need to be online to delete your account.'),
        findsOneWidget,
      );
      expect(h.account.deleted, isFalse);
      expect(h.repository.getHabits(), isNotEmpty);
    });
  });

  group('logout', () {
    testWidgets('asks for confirmation, then signs out', (tester) async {
      final h = await pumpProfile(tester);
      await openDialog(tester, 'logout-button');
      expect(find.byKey(const ValueKey('logout-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-logout')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(h.container.read(authControllerProvider), isA<SignedOut>());
    });
  });

  test('initialsFor and signInMethodLabel', () {
    expect(initialsFor('Quest Hero', 'x@y.z'), 'QH');
    expect(initialsFor('  ', 'brave.sprout@y.z'), 'BS');
    expect(initialsFor(null, 'hero@y.z'), 'H');
    expect(initialsFor('émile', ''), 'É');
    expect(initialsFor(null, ''), '?');
    expect(signInMethodLabel(const ['email']), 'Email & password');
    expect(signInMethodLabel(const ['google', 'apple']), 'Google · Apple');
    expect(validateNewPassword('abcdef', 'x'), isNull);
    expect(validateNewPassword('a' * 73, 'x'), isNotNull);
  });
}
