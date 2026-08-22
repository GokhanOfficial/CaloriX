import 'package:flutter_test/flutter_test.dart';

import 'package:calorix/core/updates/update_manifest.dart';

void main() {
  group('decideUpdate', () {
    test('cihaz minSupported altındaysa zorunlu', () {
      expect(
        decideUpdate(
          deviceVersionCode: 1,
          minSupportedVersionCode: 2,
          latestVersionCode: 3,
        ),
        UpdateDecision.required,
      );
    });

    test('cihaz desteklenen ama eski sürümde → opsiyonel', () {
      expect(
        decideUpdate(
          deviceVersionCode: 2,
          minSupportedVersionCode: 2,
          latestVersionCode: 3,
        ),
        UpdateDecision.optional,
      );
    });

    test('cihaz en yeni sürümde → güncel', () {
      expect(
        decideUpdate(
          deviceVersionCode: 3,
          minSupportedVersionCode: 2,
          latestVersionCode: 3,
        ),
        UpdateDecision.upToDate,
      );
    });

    test('cihaz manifestten yeniyse (geri alma senaryosu) → güncel', () {
      expect(
        decideUpdate(
          deviceVersionCode: 5,
          minSupportedVersionCode: 2,
          latestVersionCode: 3,
        ),
        UpdateDecision.upToDate,
      );
    });

    test('min == latest (keskin cutoff) → altı zorunlu, üstü güncel', () {
      expect(
        decideUpdate(
          deviceVersionCode: 2,
          minSupportedVersionCode: 3,
          latestVersionCode: 3,
        ),
        UpdateDecision.required,
      );
      expect(
        decideUpdate(
          deviceVersionCode: 3,
          minSupportedVersionCode: 3,
          latestVersionCode: 3,
        ),
        UpdateDecision.upToDate,
      );
    });
  });

  group('UpdateManifest', () {
    test('fromJson tüm alanları okur', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': 7,
        'minSupportedVersionCode': 5,
        'apkUrl': 'https://example.com/a.apk',
        'sha256': 'abc',
        'notes': {'tr': 'tr notu', 'en': 'en note'},
        'releasedAt': '2026-08-22T10:00:00Z',
      });
      expect(m.versionCode, 7);
      expect(m.minSupportedVersionCode, 5);
      expect(m.notesFor('tr'), 'tr notu');
      expect(m.notesFor('en'), 'en note');
      expect(m.evaluate(4), UpdateDecision.required);
      expect(m.evaluate(5), UpdateDecision.optional);
      expect(m.evaluate(7), UpdateDecision.upToDate);
    });

    test('minSupportedVersionCode yoksa 1 fallback — eskiler opsiyonel görür', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': 7,
        'apkUrl': 'https://example.com/a.apk',
      });
      expect(m.minSupportedVersionCode, 1);
      expect(m.evaluate(1), UpdateDecision.optional);
      expect(m.evaluate(6), UpdateDecision.optional);
      expect(m.evaluate(7), UpdateDecision.upToDate);
    });

    test('notesFor dil fallbacki — tr notu yoksa en gösterir', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': 7,
        'apkUrl': 'u',
        'notes': {'en': 'en only'},
      });
      expect(m.notesFor('tr'), 'en only');
      expect(m.notesFor('de'), 'en only');
    });
  });
}
