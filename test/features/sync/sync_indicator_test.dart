import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/theme/app_theme.dart';
import 'package:habit_quest/data/remote/fake_habit_quest_api.dart';
import 'package:habit_quest/data/sync/change_recorder.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/sync/sync_engine.dart';
import 'package:habit_quest/features/sync/connectivity.dart';
import 'package:habit_quest/features/sync/sync_providers.dart';
import 'package:habit_quest/features/sync/ui/sync_status_indicator.dart';

import '../../helpers/test_app.dart';

void main() {
  final now = DateTime(2026, 1, 5, 10);

  Future<void> pumpChip(WidgetTester tester, SyncStatus status) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(child: SyncStatusChip(status: status, now: now)),
          ),
        ),
      );

  String semanticsOf(WidgetTester tester) => tester
      .getSemantics(find.byKey(const ValueKey('sync-indicator')))
      .label;

  testWidgets('shows synced with the last sync time', (tester) async {
    await pumpChip(
      tester,
      SyncStatus(
        phase: SyncPhase.synced,
        lastSyncedAt: now.subtract(const Duration(minutes: 5)),
      ),
    );
    expect(find.text('☁️'), findsOneWidget);
    expect(semanticsOf(tester), contains('Synced'));
    expect(semanticsOf(tester), contains('5 min ago'));
    expect(find.byKey(const ValueKey('sync-pending-badge')), findsNothing);
  });

  testWidgets('shows offline with the number of waiting changes',
      (tester) async {
    await pumpChip(
      tester,
      const SyncStatus(phase: SyncPhase.offline, pending: 3),
    );
    expect(find.text('📴'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(semanticsOf(tester), contains('Offline · 3 waiting'));
    expect(semanticsOf(tester), contains('never'));
  });

  testWidgets('shows errors with their message', (tester) async {
    await pumpChip(
      tester,
      const SyncStatus(
        phase: SyncPhase.error,
        message: "1 change couldn't sync",
        issues: [SyncIssue(SyncEntityType.habit, 'h1', 'invalid_input')],
        pending: 1,
      ),
    );
    expect(find.text('⚠️'), findsOneWidget);
    expect(semanticsOf(tester), contains("1 change couldn't sync"));
  });

  testWidgets('shows syncing with a spinning icon', (tester) async {
    await pumpChip(tester, const SyncStatus(phase: SyncPhase.syncing));
    expect(find.text('🔄'), findsOneWidget);
    expect(find.byType(RotationTransition), findsWidgets);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Quest card "Sync now" syncs and the indicator turns synced',
      (tester) async {
    final server = FakeHabitQuestApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...signedInOverrides(),
          habitRepositoryProvider.overrideWithValue(InMemoryHabitRepository()),
          clockProvider.overrideWithValue(() => now),
          habitQuestApiProvider.overrideWithValue(server),
          connectivityMonitorProvider.overrideWithValue(
            FakeConnectivityMonitor(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Column(children: [SyncStatusIndicator(), SyncNowCard()]),
          ),
        ),
      ),
    );
    expect(find.text('Ready to sync'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync-now-button')));
    await tester.pumpAndSettle();
    expect(server.calls, contains('GET habits'));
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('☁️'), findsWidgets);
    expect(find.textContaining('Last sync: just now'), findsOneWidget);
  });
}
