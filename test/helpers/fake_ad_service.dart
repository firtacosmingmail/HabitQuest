import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:habit_quest/features/ads/ad_placement.dart';
import 'package:habit_quest/features/ads/ad_service.dart';
import 'package:habit_quest/features/ads/ad_slot.dart';

/// Renders a fixed-size placeholder in an [AdFrame] for every placement,
/// so widget tests can see where ads would go.
class FakeAdService implements AdService {
  int initializeCalls = 0;

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Widget buildAd(BuildContext context, AdPlacement placement) => AdFrame(
    child: SizedBox(
      key: ValueKey('fake-ad-${placement.name}'),
      height: 50,
      child: const ColoredBox(color: Colors.amber),
    ),
  );
}

/// Overrides [adServiceProvider] with a [FakeAdService].
Override fakeAdsOverride([FakeAdService? fake]) =>
    adServiceProvider.overrideWithValue(fake ?? FakeAdService());
