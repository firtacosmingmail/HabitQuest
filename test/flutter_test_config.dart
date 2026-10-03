import 'dart:async';

import 'package:habit_quest/core/theme/app_theme.dart';

/// Applies to every test under `test/`: no Google Fonts network fetching.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppTheme.useGoogleFonts = false;
  await testMain();
}
