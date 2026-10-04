import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'app.dart';
import 'data/repositories/hive_habit_repository.dart';
import 'domain/providers.dart';
import 'features/notifications/notifications_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final repository = await HiveHabitRepository.open();

  runApp(
    ProviderScope(
      overrides: [habitRepositoryProvider.overrideWithValue(repository)],
      child: const NotificationsBootstrap(child: HabitQuestApp()),
    ),
  );
}
