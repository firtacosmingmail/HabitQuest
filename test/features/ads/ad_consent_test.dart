import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:habit_quest/features/ads/ad_consent_debug.dart';
import 'package:habit_quest/features/ads/ad_privacy_settings.dart';
import 'package:habit_quest/features/ads/ad_service.dart';
import 'package:habit_quest/features/ads/platform_ad_service_mobile.dart';

import '../../helpers/fake_ad_service.dart';
import '../../helpers/test_app.dart';

void main() {
  group('ConsentDebugConfig.resolve', () {
    test('no defines: off', () {
      final c = ConsentDebugConfig.resolve(isRelease: false);
      expect(c.geography, ConsentDebugGeography.none);
      expect(c.testDeviceIds, isEmpty);
      expect(c.resetOnStart, isFalse);
      expect(c.isActive, isFalse);
      expect(c.hasDebugSettings, isFalse);
    });

    test('eea + test device + reset in debug', () {
      final c = ConsentDebugConfig.resolve(
        geographyDefine: ' EEA ',
        testDeviceIdDefine: 'ABC123, DEF456 ,',
        resetDefine: 'true',
        isRelease: false,
      );
      expect(c.geography, ConsentDebugGeography.eea);
      expect(c.testDeviceIds, ['ABC123', 'DEF456']);
      expect(c.resetOnStart, isTrue);
      expect(c.hasDebugSettings, isTrue);
    });

    test('us and other geographies; unknown is ignored', () {
      ConsentDebugGeography g(String v) =>
          ConsentDebugConfig.resolve(geographyDefine: v, isRelease: false)
              .geography;
      expect(g('us'), ConsentDebugGeography.regulatedUsState);
      expect(g('regulated_us_state'), ConsentDebugGeography.regulatedUsState);
      expect(g('other'), ConsentDebugGeography.other);
      expect(g('mars'), ConsentDebugGeography.none);
    });

    test('release builds ignore every define', () {
      final c = ConsentDebugConfig.resolve(
        geographyDefine: 'eea',
        testDeviceIdDefine: 'ABC123',
        resetDefine: 'true',
        isRelease: true,
      );
      expect(c.isActive, isFalse);
      expect(c.geography, ConsentDebugGeography.none);
      expect(c.testDeviceIds, isEmpty);
      expect(c.resetOnStart, isFalse);
    });

    test('fromEnvironment is off without defines (test run)', () {
      expect(ConsentDebugConfig.fromEnvironment().isActive, isFalse);
    });
  });

  group('consentRequestParameters', () {
    test('no debug settings when off', () {
      final p = consentRequestParameters(ConsentDebugConfig.off);
      expect(p.consentDebugSettings, isNull);
    });

    test('eea + test device map to ConsentDebugSettings', () {
      final p = consentRequestParameters(
        ConsentDebugConfig.resolve(
          geographyDefine: 'eea',
          testDeviceIdDefine: 'ABC123',
          isRelease: false,
        ),
      );
      expect(
        p.consentDebugSettings!.debugGeography,
        DebugGeography.debugGeographyEea,
      );
      expect(p.consentDebugSettings!.testIdentifiers, ['ABC123']);
    });

    test('us maps to the regulated US state geography', () {
      final p = consentRequestParameters(
        ConsentDebugConfig.resolve(geographyDefine: 'us', isRelease: false),
      );
      expect(
        p.consentDebugSettings!.debugGeography,
        DebugGeography.debugGeographyRegulatedUsState,
      );
      expect(p.consentDebugSettings!.testIdentifiers, isNull);
    });

    test('release config yields plain parameters', () {
      final p = consentRequestParameters(
        ConsentDebugConfig.resolve(
          geographyDefine: 'eea',
          testDeviceIdDefine: 'ABC123',
          isRelease: true,
        ),
      );
      expect(p.consentDebugSettings, isNull);
    });
  });

  group('AdPrivacySettings (Settings screen)', () {
    Finder key(String k) => find.byKey(ValueKey(k));

    Future<void> pumpSettings(WidgetTester tester, FakeAdService fake) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHabitQuestApp(
        tester,
        initialLocation: '/profile/settings',
        overrides: [fakeAdsOverride(fake)],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('privacy choices entry when UMP requires it', (tester) async {
      final fake = FakeAdService(privacyRequired: true);
      await pumpSettings(tester, fake);
      expect(key('settings-ad-privacy'), findsOneWidget);
      await tester.tap(key('settings-ad-privacy'));
      await tester.pumpAndSettle();
      expect(fake.showPrivacyOptionsCalls, 1);
    });

    testWidgets('nothing when not required and no consent service', (
      tester,
    ) async {
      await pumpSettings(tester, FakeAdService());
      expect(key('settings-ad-privacy'), findsNothing);
      expect(key('settings-ad-consent-reset'), findsNothing);
      expect(find.text('Ads & privacy'), findsNothing);
    });

    testWidgets('debug reset tile in debug builds', (tester) async {
      final fake = FakeAdService(managesConsent: true);
      await pumpSettings(tester, fake);
      expect(key('settings-ad-privacy'), findsNothing);
      await tester.tap(key('settings-ad-consent-reset'));
      await tester.pumpAndSettle();
      expect(fake.resetConsentCalls, 1);
    });

    testWidgets('no debug reset tile when disabled (as in release)', (
      tester,
    ) async {
      final fake = FakeAdService(managesConsent: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adServiceProvider.overrideWithValue(fake)],
          child: const MaterialApp(
            home: Scaffold(body: AdPrivacySettings(showDebugReset: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(key('settings-ad-consent-reset'), findsNothing);
    });
  });
}
